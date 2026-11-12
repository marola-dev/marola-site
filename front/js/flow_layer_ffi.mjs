// Why this file exists: MapLibre has no particle layer, so the wind and wave animation (ported
// from site/static/flow.js) is a raw WebGL CustomLayerInterface that maplibre_ffi.mjs adds.
// Elm builds the field (FlowData.elm); sampling, particles and drawing run here every frame.
//
// Matrix: render() uses options.defaultProjectionData.mainMatrix, which the d.ts documents as
// the plain projection matrix for custom layers. Checked in vendored maplibre-gl.mjs: the mercator
// getProjectionDataForCustomLayer takes the tile 0/0/0 position matrix (viewProj * scale(worldSize
// / 8192)) and scales x and y by 8192, so mainMatrix = viewProj * scale(worldSize): mercator 0..1
// world coordinates to clip space, which is what Flow.elm's grid uses. modelViewProjectionMatrix
// is the unscaled viewProj (world pixels), so it is not used. Globe projection is never enabled.
// MapLibre 6 hands over a WebGL2 context, so the shaders are GLSL ES 3.00.

const KINDS = {
  wind: { px: 1.6, density: 1 / 450, trail: 14, life: [40, 110], color: [1, 1, 1] },
  waves: { px: 0.55, density: 1 / 900, trail: 18, life: [70, 160], color: [0.93, 0.9, 1] },
};
const V = "#version 300 es\n";
const FIELD_VS = V + "in vec2 a_pos; uniform mat4 u_matrix; uniform vec4 u_box; out vec2 v_uv;" +
  "void main() { v_uv = a_pos; gl_Position = u_matrix * vec4(mix(u_box.xy, u_box.zw, a_pos), 0.0, 1.0); }";
// the box's own edge fades too, or a far-off beach leaves a visible rectangle
const FIELD_FS = V + "precision mediump float; uniform sampler2D u_field; uniform sampler2D u_ramp;" +
  "uniform float u_opacity; in vec2 v_uv; out vec4 o;" +
  "void main() { vec4 f = texture(u_field, v_uv); vec3 c = texture(u_ramp, vec2(f.r, 0.5)).rgb;" +
  " vec2 e = smoothstep(0.0, 0.15, v_uv) * smoothstep(0.0, 0.15, 1.0 - v_uv);" +
  " float a = f.a * e.x * e.y * u_opacity; o = vec4(c * a, a); }";
const LINE_VS = V + "in vec2 a_pos; in float a_alpha; uniform mat4 u_matrix; out float v_alpha;" +
  "void main() { v_alpha = a_alpha; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }";
const LINE_FS = V + "precision mediump float; uniform vec3 u_color; in float v_alpha; out vec4 o;" +
  "void main() { o = vec4(u_color * v_alpha, v_alpha); }";

const mercX = (lon) => (lon + 180) / 360;
const mercY = (lat) => {
  const s = Math.sin((lat * Math.PI) / 180);
  return Math.min(1, Math.max(0, 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)));
};

// Bilinear sample at a mercator point: [u, v, m, a], or null outside the field.
function sample(f, x, y) {
  const gx = ((x - f.x0) / (f.x1 - f.x0)) * f.w - 0.5, gy = ((y - f.y0) / (f.y1 - f.y0)) * f.h - 0.5;
  if (!(gx >= -0.5 && gy >= -0.5 && gx <= f.w - 0.5 && gy <= f.h - 0.5)) return null;
  const i0 = Math.max(0, Math.min(f.w - 1, Math.floor(gx))), j0 = Math.max(0, Math.min(f.h - 1, Math.floor(gy)));
  const i1 = Math.min(f.w - 1, i0 + 1), j1 = Math.min(f.h - 1, j0 + 1);
  const tx = Math.max(0, Math.min(1, gx - i0)), ty = Math.max(0, Math.min(1, gy - j0));
  const at = (arr) => {
    const a = arr[j0 * f.w + i0] * (1 - tx) + arr[j0 * f.w + i1] * tx;
    const b = arr[j1 * f.w + i0] * (1 - tx) + arr[j1 * f.w + i1] * tx;
    return a * (1 - ty) + b * ty;
  };
  return [at(f.u), at(f.v), at(f.m), at(f.a)];
}

function hexRgb(hex) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(hex).trim());
  return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [140, 140, 140];
}

// Evenly spaced stops to 256 RGBA texels; no ramp means flat grey.
function rampPixels(stops) {
  const rgb = (stops && stops.length ? stops : ["#8c8c8c"]).map(hexRgb);
  if (rgb.length < 2) rgb.push(rgb[0]);
  const out = new Uint8Array(256 * 4);
  for (let i = 0; i < 256; i++) {
    const t = (i / 255) * (rgb.length - 1), k = Math.min(rgb.length - 2, Math.floor(t)), f = t - k;
    for (let c = 0; c < 3; c++) out[i * 4 + c] = Math.round(rgb[k][c] * (1 - f) + rgb[k + 1][c] * f);
    out[i * 4 + 3] = 255;
  }
  return out;
}

function program(gl, vs, fs) {
  const shader = (type, src) => {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error("flow shader: " + gl.getShaderInfoLog(s));
    return s;
  };
  const p = gl.createProgram();
  gl.attachShader(p, shader(gl.VERTEX_SHADER, vs));
  gl.attachShader(p, shader(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error("flow program: " + gl.getProgramInfoLog(p));
  return p;
}

function texture(gl, w, h, pixels) {
  const t = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  for (const [name, value] of [["MIN_FILTER", gl.LINEAR], ["MAG_FILTER", gl.LINEAR],
    ["WRAP_S", gl.CLAMP_TO_EDGE], ["WRAP_T", gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, gl["TEXTURE_" + name], value);
  return t;
}

export function createFlowLayer(id) {
  const still = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  let map = null, gl = null, field = null, K = KINDS.wind, dirty = true, last = 0;
  let P = null; // particles: n, t, x, y (n*t ring), age, life, head, verts
  let fieldProg, lineProg, quad, lines, fieldTex, rampTex;
  const onVisible = () => { if (!document.hidden && map) map.triggerRepaint(); };
  const loc = (p, name) => gl.getUniformLocation(p, name);

  function view() {
    const b = map.getBounds();
    return { x0: Math.max(field.x0, mercX(b.getWest())), x1: Math.min(field.x1, mercX(b.getEast())),
      y0: Math.max(field.y0, mercY(b.getNorth())), y1: Math.min(field.y1, mercY(b.getSouth())) };
  }

  function spawn(i, v) {
    let x = 0, y = 0, ok = false;
    if (v.x1 > v.x0 && v.y1 > v.y0) {
      for (let tries = 0; tries < 8 && !ok; tries++) {
        x = v.x0 + Math.random() * (v.x1 - v.x0);
        y = v.y0 + Math.random() * (v.y1 - v.y0);
        const s = sample(field, x, y);
        ok = !!s && Math.random() < s[3];
      }
    }
    for (let k = 0; k < P.t; k++) { P.x[i * P.t + k] = x; P.y[i * P.t + k] = y; }
    P.life[i] = K.life[0] + Math.random() * (K.life[1] - K.life[0]);
    P.age[i] = ok ? 0 : P.life[i] + 1; // nowhere to put it: dead, retried next frame
  }

  function step(dt) {
    const v = view(), perPx = 1 / (512 * Math.pow(2, map.getZoom())), next = (P.head + 1) % P.t;
    for (let i = 0; i < P.n; i++) {
      const o = i * P.t, x = P.x[o + P.head], y = P.y[o + P.head], s = sample(field, x, y);
      P.age[i] += dt;
      if (!s || P.age[i] > P.life[i] || x < v.x0 || x > v.x1 || y < v.y0 || y > v.y1) { spawn(i, v); continue; }
      const mag = Math.sqrt(s[0] * s[0] + s[1] * s[1]) || 1, px = K.px * (0.25 + 0.75 * s[2]) * dt * perPx;
      P.x[o + next] = x + (s[0] / mag) * px;
      P.y[o + next] = y - (s[1] / mag) * px; // mercator y grows southwards
    }
    P.head = next;
  }

  function particles() {
    const c = map.getCanvas(), n = Math.max(150, Math.min(3000, Math.round(c.clientWidth * c.clientHeight * K.density)));
    P = { n, t: K.trail, head: 0, x: new Float32Array(n * K.trail), y: new Float32Array(n * K.trail),
      age: new Float32Array(n), life: new Float32Array(n), verts: new Float32Array(n * (K.trail - 1) * 6) };
    const v = view();
    for (let i = 0; i < n; i++) { spawn(i, v); if (P.age[i] === 0) P.age[i] = Math.random() * P.life[i]; }
    // a still map (reduced motion) shows each particle's whole trail at once
    if (still) for (let s = 0; s < P.t; s++) step(1);
  }

  function buildLines() {
    let n = 0;
    const T = P.t, out = P.verts;
    for (let i = 0; i < P.n; i++) {
      const o = i * T, s = sample(field, P.x[o + P.head], P.y[o + P.head]);
      if (!s) continue;
      const age = P.age[i], fade = Math.min(1, age / 12, (P.life[i] - age) / 12);
      const base = Math.max(0, fade) * Math.min(1, s[3] * 1.4) * (0.55 + 0.45 * s[2]);
      if (base < 0.02) continue;
      for (let k = 0; k < T - 1; k++) {
        const a = (P.head - k + T) % T, b = (P.head - k - 1 + T) % T;
        if (P.x[o + a] === P.x[o + b] && P.y[o + a] === P.y[o + b]) break;
        out[n++] = P.x[o + a]; out[n++] = P.y[o + a]; out[n++] = base * (1 - k / (T - 1));
        out[n++] = P.x[o + b]; out[n++] = P.y[o + b]; out[n++] = base * (1 - (k + 1) / (T - 1));
      }
    }
    return n / 3;
  }

  function upload() {
    const cells = field.w * field.h, px = new Uint8Array(cells * 4);
    for (let n = 0; n < cells; n++) { px[n * 4] = Math.round(field.m[n] * 255); px[n * 4 + 3] = Math.round(field.a[n] * 255); }
    for (const t of [fieldTex, rampTex]) if (t) gl.deleteTexture(t);
    fieldTex = texture(gl, field.w, field.h, px);
    rampTex = texture(gl, 256, 1, rampPixels(field.ramp));
    dirty = false;
  }

  function drawField(m) {
    gl.useProgram(fieldProg);
    gl.bindBuffer(gl.ARRAY_BUFFER, quad);
    const a = gl.getAttribLocation(fieldProg, "a_pos");
    gl.enableVertexAttribArray(a);
    gl.vertexAttribPointer(a, 2, gl.FLOAT, false, 0, 0);
    gl.uniformMatrix4fv(loc(fieldProg, "u_matrix"), false, m);
    gl.uniform4f(loc(fieldProg, "u_box"), field.x0, field.y0, field.x1, field.y1);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, fieldTex);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, rampTex);
    gl.uniform1i(loc(fieldProg, "u_field"), 0);
    gl.uniform1i(loc(fieldProg, "u_ramp"), 1);
    gl.uniform1f(loc(fieldProg, "u_opacity"), 0.65);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.disableVertexAttribArray(a);
  }

  function drawLines(m, count) {
    gl.useProgram(lineProg);
    gl.bindBuffer(gl.ARRAY_BUFFER, lines);
    gl.bufferData(gl.ARRAY_BUFFER, P.verts.subarray(0, count * 3), gl.DYNAMIC_DRAW);
    const lp = gl.getAttribLocation(lineProg, "a_pos"), la = gl.getAttribLocation(lineProg, "a_alpha");
    for (const a of [lp, la]) gl.enableVertexAttribArray(a);
    gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 12, 0);
    gl.vertexAttribPointer(la, 1, gl.FLOAT, false, 12, 8);
    gl.uniformMatrix4fv(loc(lineProg, "u_matrix"), false, m);
    gl.uniform3f(loc(lineProg, "u_color"), K.color[0], K.color[1], K.color[2]);
    gl.drawArrays(gl.LINES, 0, count);
    for (const a of [lp, la]) gl.disableVertexAttribArray(a);
  }

  return {
    id, type: "custom", renderingMode: "2d",
    onAdd(m, g) {
      map = m; gl = g;
      fieldProg = program(gl, FIELD_VS, FIELD_FS);
      lineProg = program(gl, LINE_VS, LINE_FS);
      quad = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, quad);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
      lines = gl.createBuffer(); dirty = true;
      document.addEventListener("visibilitychange", onVisible);
    },
    onRemove() {
      document.removeEventListener("visibilitychange", onVisible);
      if (!gl) return;
      for (const p of [fieldProg, lineProg]) gl.deleteProgram(p);
      for (const b of [quad, lines]) gl.deleteBuffer(b);
      for (const t of [fieldTex, rampTex]) if (t) gl.deleteTexture(t);
      fieldTex = rampTex = P = map = gl = null;
    },
    setField(f) {
      field = f; K = KINDS[f && f.kind] || KINDS.wind; dirty = true; P = null;
      if (map) map.triggerRepaint();
    },
    render(g, options) {
      if (!field || !gl) return;
      if (dirty) upload();
      const m = options.defaultProjectionData.mainMatrix, now = Date.now();
      gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      drawField(m);
      if (!P) { particles(); last = now; }
      else if (!still) { step(Math.min(3, (now - last) / (1000 / 60) || 1)); last = now; }
      const count = buildLines();
      if (count) drawLines(m, count);
      if (!still && !document.hidden) map.triggerRepaint();
    },
  };
}
