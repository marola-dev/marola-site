/** marola flow: animated wind and wave particles over the map, drawn with WebGL in a Mapbox GL
 * custom layer. The field is interpolated from the board's own beach readings (no weather grid is
 * fetched), so it is an estimate between beaches and fades out away from them. */
(function () {
  'use strict';

  var KM_PER_DEG = 111.32;
  // max: the top of the colour ramp. px: screen pixels a particle moves per frame at max.
  var KINDS = {
    wind: { max: 40, px: 1.6, density: 1 / 450, trail: 14, life: [40, 110], color: [1, 1, 1] },
    waves: { max: 3, px: 0.55, density: 1 / 900, trail: 18, life: [70, 160], color: [0.93, 0.9, 1] }
  };
  var PAD_KM = 30;     // the field reaches this far past the outermost beach
  var REACH_KM = 18;   // and fades out over about this distance from the nearest one
  var GRID = 96;

  function mercX(lon) { return (lon + 180) / 360; }
  function mercY(lat) {
    var s = Math.sin(lat * Math.PI / 180);
    return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
  }
  function lonOf(x) { return x * 360 - 180; }
  function latOf(y) { return 360 / Math.PI * Math.atan(Math.exp((1 - 2 * y) * Math.PI)) - 90; }

  /** points: [{lon, lat, mag, dir}], dir in degrees the flow comes FROM (Open-Meteo's convention).
   * Returns a GRID² field in mercator space: u/v (east/north, in units of mag), m (mag / max, 0..1)
   * and a (how close the nearest beach is, 0..1). Null when no point has both numbers. */
  function buildField(points, max) {
    var pts = (points || []).filter(function (p) {
      return isFinite(p.lon) && isFinite(p.lat) && typeof p.mag === 'number' && typeof p.dir === 'number';
    });
    if (!pts.length) return null;
    var lat0 = pts.reduce(function (s, p) { return s + p.lat; }, 0) / pts.length;
    var kx = KM_PER_DEG * Math.cos(lat0 * Math.PI / 180), ky = KM_PER_DEG;
    var minLon = Infinity, maxLon = -Infinity, minLat = Infinity, maxLat = -Infinity;
    pts.forEach(function (p) {
      minLon = Math.min(minLon, p.lon); maxLon = Math.max(maxLon, p.lon);
      minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    });
    minLon -= PAD_KM / kx; maxLon += PAD_KM / kx; minLat -= PAD_KM / ky; maxLat += PAD_KM / ky;
    var f = { w: GRID, h: GRID, x0: mercX(minLon), x1: mercX(maxLon), y0: mercY(maxLat), y1: mercY(minLat), max: max,
      u: new Float32Array(GRID * GRID), v: new Float32Array(GRID * GRID), m: new Float32Array(GRID * GRID), a: new Float32Array(GRID * GRID) };
    var vec = pts.map(function (p) {
      var to = (p.dir + 180) * Math.PI / 180; // the board says where it comes from; particles go the other way
      return { x: p.lon * kx, y: p.lat * ky, u: Math.sin(to) * p.mag, v: Math.cos(to) * p.mag, mag: p.mag };
    });
    for (var j = 0; j < GRID; j++) {
      var lat = latOf(f.y0 + (f.y1 - f.y0) * (j + 0.5) / GRID);
      for (var i = 0; i < GRID; i++) {
        var lon = lonOf(f.x0 + (f.x1 - f.x0) * (i + 0.5) / GRID);
        var sw = 0, su = 0, sv = 0, sm = 0, dmin = Infinity;
        for (var k = 0; k < vec.length; k++) {
          var dx = lon * kx - vec[k].x, dy = lat * ky - vec[k].y, d2 = dx * dx + dy * dy;
          dmin = Math.min(dmin, d2);
          var w = 1 / (d2 + 0.25);
          sw += w; su += w * vec[k].u; sv += w * vec[k].v; sm += w * vec[k].mag;
        }
        var n = j * GRID + i;
        f.u[n] = su / sw; f.v[n] = sv / sw;
        f.m[n] = Math.min(1, sm / sw / max);
        f.a[n] = Math.exp(-dmin / (REACH_KM * REACH_KM));
      }
    }
    return f;
  }

  /** Bilinear sample at a mercator point: [u, v, m, a], or null outside the field. */
  function sample(f, x, y) {
    var gx = (x - f.x0) / (f.x1 - f.x0) * f.w - 0.5, gy = (y - f.y0) / (f.y1 - f.y0) * f.h - 0.5;
    if (!(gx >= -0.5 && gy >= -0.5 && gx <= f.w - 0.5 && gy <= f.h - 0.5)) return null;
    var i0 = Math.max(0, Math.min(f.w - 1, Math.floor(gx))), j0 = Math.max(0, Math.min(f.h - 1, Math.floor(gy)));
    var i1 = Math.min(f.w - 1, i0 + 1), j1 = Math.min(f.h - 1, j0 + 1);
    var tx = Math.max(0, Math.min(1, gx - i0)), ty = Math.max(0, Math.min(1, gy - j0));
    function at(arr) {
      var a = arr[j0 * f.w + i0] * (1 - tx) + arr[j0 * f.w + i1] * tx;
      var b = arr[j1 * f.w + i0] * (1 - tx) + arr[j1 * f.w + i1] * tx;
      return a * (1 - ty) + b * ty;
    }
    return [at(f.u), at(f.v), at(f.m), at(f.a)];
  }

  function hexRgb(hex) {
    var m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(hex).trim());
    return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [255, 255, 255];
  }
  /** Evenly spaced stops → 256 RGBA texels. */
  function rampPixels(stops) {
    var rgb = stops.map(hexRgb), out = new Uint8Array(256 * 4);
    for (var i = 0; i < 256; i++) {
      var t = i / 255 * (rgb.length - 1), k = Math.min(rgb.length - 2, Math.floor(t)), f = t - k;
      for (var c = 0; c < 3; c++) out[i * 4 + c] = Math.round(rgb[k][c] * (1 - f) + rgb[k + 1][c] * f);
      out[i * 4 + 3] = 255;
    }
    return out;
  }

  // --- WebGL ---------------------------------------------------------------------------------.
  var FIELD_VS = 'attribute vec2 a_pos; uniform mat4 u_matrix; uniform vec4 u_box; varying vec2 v_uv;' +
    'void main() { v_uv = a_pos; gl_Position = u_matrix * vec4(mix(u_box.xy, u_box.zw, a_pos), 0.0, 1.0); }';
  var FIELD_FS = 'precision mediump float; uniform sampler2D u_field; uniform sampler2D u_ramp; uniform float u_opacity; varying vec2 v_uv;' +
    'void main() { vec4 f = texture2D(u_field, v_uv); vec3 c = texture2D(u_ramp, vec2(f.r, 0.5)).rgb;' +
    // the box's own edge fades too, or a far-off beach leaves a visible rectangle
    ' vec2 e = smoothstep(0.0, 0.15, v_uv) * smoothstep(0.0, 0.15, 1.0 - v_uv); float a = f.a * e.x * e.y * u_opacity;' +
    ' gl_FragColor = vec4(c * a, a); }';
  var LINE_VS = 'attribute vec2 a_pos; attribute float a_alpha; uniform mat4 u_matrix; varying float v_alpha;' +
    'void main() { v_alpha = a_alpha; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }';
  var LINE_FS = 'precision mediump float; uniform vec3 u_color; varying float v_alpha;' +
    'void main() { gl_FragColor = vec4(u_color * v_alpha, v_alpha); }';

  function program(gl, vs, fs) {
    function shader(type, src) {
      var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error('flow shader: ' + gl.getShaderInfoLog(s));
      return s;
    }
    var p = gl.createProgram();
    gl.attachShader(p, shader(gl.VERTEX_SHADER, vs)); gl.attachShader(p, shader(gl.FRAGMENT_SHADER, fs));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error('flow program: ' + gl.getProgramInfoLog(p));
    return p;
  }
  function texture(gl, w, h, pixels) {
    var t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return t;
  }

  /** A Mapbox GL custom layer. opts: {id, ramps: {wind: [hex…], waves: [hex…]}, still}. */
  function layer(opts) {
    var self = { id: opts.id || 'marola-flow', type: 'custom', renderingMode: '2d' };
    var map = null, gl = null, kind = 'off', data = {}, field = null, dirty = true;
    var fieldProg, lineProg, quad, lines, fieldTex = null, rampTex = {};
    var P = null; // particles: {n, t, x, y (n*t ring), age, life, head, verts}
    var last = 0;
    var still = !!opts.still;

    function setUp() {
      field = kind === 'off' ? null : buildField(data[kind], KINDS[kind].max);
      dirty = true; P = null;
      if (map) map.triggerRepaint();
    }
    self.setKind = function (k) { kind = KINDS[k] ? k : 'off'; setUp(); };
    self.setData = function (d) { data = d || {}; setUp(); };
    self.kind = function () { return kind; };
    self.field = function () { return field; };

    self.onAdd = function (m, g) {
      map = m; gl = g;
      fieldProg = program(gl, FIELD_VS, FIELD_FS);
      lineProg = program(gl, LINE_VS, LINE_FS);
      quad = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, quad);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
      lines = gl.createBuffer();
      Object.keys(KINDS).forEach(function (k) { rampTex[k] = texture(gl, 256, 1, rampPixels(opts.ramps[k])); });
      document.addEventListener('visibilitychange', function () { if (!document.hidden && map) map.triggerRepaint(); });
    };
    self.onRemove = function () {
      if (!gl) return;
      [fieldProg, lineProg].forEach(function (p) { gl.deleteProgram(p); });
      [quad, lines].forEach(function (b) { gl.deleteBuffer(b); });
      Object.keys(rampTex).forEach(function (k) { gl.deleteTexture(rampTex[k]); });
      if (fieldTex) gl.deleteTexture(fieldTex);
      map = gl = null;
    };

    function uploadField() {
      var px = new Uint8Array(field.w * field.h * 4);
      for (var n = 0; n < field.w * field.h; n++) {
        px[n * 4] = Math.round(field.m[n] * 255);
        px[n * 4 + 3] = Math.round(field.a[n] * 255);
      }
      if (fieldTex) gl.deleteTexture(fieldTex);
      fieldTex = texture(gl, field.w, field.h, px);
      dirty = false;
    }

    function view() {
      var b = map.getBounds();
      return { x0: Math.max(field.x0, mercX(b.getWest())), x1: Math.min(field.x1, mercX(b.getEast())),
        y0: Math.max(field.y0, mercY(b.getNorth())), y1: Math.min(field.y1, mercY(b.getSouth())) };
    }
    function spawn(i, v) {
      var K = KINDS[kind], x = 0, y = 0, ok = false;
      if (v.x1 > v.x0 && v.y1 > v.y0) {
        for (var tries = 0; tries < 8 && !ok; tries++) {
          x = v.x0 + Math.random() * (v.x1 - v.x0); y = v.y0 + Math.random() * (v.y1 - v.y0);
          var s = sample(field, x, y);
          ok = !!s && Math.random() < s[3];
        }
      }
      for (var k = 0; k < P.t; k++) { P.x[i * P.t + k] = x; P.y[i * P.t + k] = y; }
      P.life[i] = K.life[0] + Math.random() * (K.life[1] - K.life[0]);
      P.age[i] = ok ? 0 : P.life[i] + 1; // nowhere to put it: dead, retried next frame
    }
    function particles() {
      var K = KINDS[kind], c = map.getCanvas();
      var n = Math.max(150, Math.min(3000, Math.round(c.clientWidth * c.clientHeight * K.density)));
      P = { n: n, t: K.trail, head: 0, x: new Float32Array(n * K.trail), y: new Float32Array(n * K.trail),
        age: new Float32Array(n), life: new Float32Array(n), verts: new Float32Array(n * (K.trail - 1) * 6) };
      var v = view();
      for (var i = 0; i < n; i++) { spawn(i, v); if (P.age[i] === 0) P.age[i] = Math.random() * P.life[i]; }
      // a still map (reduced motion) shows each particle's whole trail at once
      var steps = still ? P.t : 0;
      for (var s = 0; s < steps; s++) step(1);
    }
    function step(dt) {
      var K = KINDS[kind], v = view();
      var perPx = 1 / (512 * Math.pow(2, map.getZoom()));
      var next = (P.head + 1) % P.t;
      for (var i = 0; i < P.n; i++) {
        var o = i * P.t, x = P.x[o + P.head], y = P.y[o + P.head];
        var s = sample(field, x, y);
        P.age[i] += dt;
        if (!s || P.age[i] > P.life[i] || x < v.x0 || x > v.x1 || y < v.y0 || y > v.y1) { spawn(i, v); continue; }
        var mag = Math.sqrt(s[0] * s[0] + s[1] * s[1]) || 1;
        var px = K.px * (0.25 + 0.75 * s[2]) * dt * perPx;
        P.x[o + next] = x + s[0] / mag * px;
        P.y[o + next] = y - s[1] / mag * px; // mercator y grows southwards
      }
      P.head = next;
    }
    function buildLines() {
      var n = 0, T = P.t, out = P.verts;
      for (var i = 0; i < P.n; i++) {
        var o = i * T, x = P.x[o + P.head], y = P.y[o + P.head];
        var s = sample(field, x, y);
        if (!s) continue;
        var age = P.age[i], fade = Math.min(1, age / 12, (P.life[i] - age) / 12);
        var base = Math.max(0, fade) * Math.min(1, s[3] * 1.4) * (0.55 + 0.45 * s[2]);
        if (base < 0.02) continue;
        for (var k = 0; k < T - 1; k++) {
          var a = (P.head - k + T) % T, b = (P.head - k - 1 + T) % T;
          if (P.x[o + a] === P.x[o + b] && P.y[o + a] === P.y[o + b]) break;
          out[n++] = P.x[o + a]; out[n++] = P.y[o + a]; out[n++] = base * (1 - k / (T - 1));
          out[n++] = P.x[o + b]; out[n++] = P.y[o + b]; out[n++] = base * (1 - (k + 1) / (T - 1));
        }
      }
      return n / 3;
    }

    self.render = function (g, matrix) {
      if (!field || !gl) return;
      if (dirty) uploadField();
      var m = new Float32Array(matrix);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);

      gl.useProgram(fieldProg);
      gl.bindBuffer(gl.ARRAY_BUFFER, quad);
      var aPos = gl.getAttribLocation(fieldProg, 'a_pos');
      gl.enableVertexAttribArray(aPos);
      gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
      gl.uniformMatrix4fv(gl.getUniformLocation(fieldProg, 'u_matrix'), false, m);
      gl.uniform4f(gl.getUniformLocation(fieldProg, 'u_box'), field.x0, field.y0, field.x1, field.y1);
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, fieldTex);
      gl.uniform1i(gl.getUniformLocation(fieldProg, 'u_field'), 0);
      gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, rampTex[kind]);
      gl.uniform1i(gl.getUniformLocation(fieldProg, 'u_ramp'), 1);
      gl.uniform1f(gl.getUniformLocation(fieldProg, 'u_opacity'), 0.55);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.disableVertexAttribArray(aPos);

      var now = Date.now();
      if (!P) { particles(); last = now; }
      else if (!still) { step(Math.min(3, (now - last) / (1000 / 60) || 1)); last = now; }
      var count = buildLines();
      if (count) {
        gl.useProgram(lineProg);
        gl.bindBuffer(gl.ARRAY_BUFFER, lines);
        gl.bufferData(gl.ARRAY_BUFFER, P.verts.subarray(0, count * 3), gl.DYNAMIC_DRAW);
        var lp = gl.getAttribLocation(lineProg, 'a_pos'), la = gl.getAttribLocation(lineProg, 'a_alpha');
        gl.enableVertexAttribArray(lp); gl.enableVertexAttribArray(la);
        gl.vertexAttribPointer(lp, 2, gl.FLOAT, false, 12, 0);
        gl.vertexAttribPointer(la, 1, gl.FLOAT, false, 12, 8);
        gl.uniformMatrix4fv(gl.getUniformLocation(lineProg, 'u_matrix'), false, m);
        var col = KINDS[kind].color;
        gl.uniform3f(gl.getUniformLocation(lineProg, 'u_color'), col[0], col[1], col[2]);
        gl.drawArrays(gl.LINES, 0, count);
        gl.disableVertexAttribArray(lp); gl.disableVertexAttribArray(la);
      }
      if (!still && !document.hidden) map.triggerRepaint();
    };
    return self;
  }

  window.marolaFlow = { KINDS: KINDS, buildField: buildField, sample: sample, rampPixels: rampPixels, layer: layer, mercX: mercX, mercY: mercY };
})();
