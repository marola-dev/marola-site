/** Wind and wave particles in a Mapbox GL custom layer, interpolated from the board's beach readings (no weather
 * grid): an estimate between beaches that fades away from them. */
export type Kind = 'wind' | 'waves';

export interface FlowPoint {
  lon: number;
  lat: number;
  mag: number | null;
  dir: number | null; // degrees the flow comes FROM (Open-Meteo's convention)
}

export interface Field {
  w: number;
  h: number;
  x0: number;
  x1: number;
  y0: number;
  y1: number;
  max: number;
  u: Float32Array;
  v: Float32Array;
  m: Float32Array; // mag / max, 0..1
  a: Float32Array; // how close the nearest beach is, 0..1
}

const KM_PER_DEG = 111.32;
// max: the top of the colour ramp. px: screen pixels a particle moves per frame at max.
export const KINDS = {
  wind: { max: 40, px: 1.6, density: 1 / 450, trail: 14, life: [40, 110], color: [1, 1, 1] },
  waves: { max: 3, px: 0.55, density: 1 / 900, trail: 18, life: [70, 160], color: [0.93, 0.9, 1] },
} as const satisfies Record<Kind, { max: number; px: number; density: number; trail: number; life: readonly [number, number]; color: readonly [number, number, number] }>;
const PAD_KM = 30; // the field reaches this far past the outermost beach
const REACH_KM = 18; // and fades out over about this distance from the nearest one
const GRID = 96;

export const mercX = (lon: number): number => (lon + 180) / 360;
export function mercY(lat: number): number {
  const s = Math.sin((lat * Math.PI) / 180);
  return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
}
const lonOf = (x: number): number => x * 360 - 180;
const latOf = (y: number): number => (360 / Math.PI) * Math.atan(Math.exp((1 - 2 * y) * Math.PI)) - 90;

/** A GRID² field in mercator space; null when no point has both numbers (a missing one is never read as zero). */
export function buildField(points: readonly FlowPoint[], max: number): Field | null {
  const pts = points.flatMap((p) =>
    Number.isFinite(p.lon) && Number.isFinite(p.lat) && typeof p.mag === 'number' && typeof p.dir === 'number' ? [{ lon: p.lon, lat: p.lat, mag: p.mag, dir: p.dir }] : [],
  );
  if (!pts.length) return null;
  const lat0 = pts.reduce((s, p) => s + p.lat, 0) / pts.length;
  const kx = KM_PER_DEG * Math.cos((lat0 * Math.PI) / 180);
  const ky = KM_PER_DEG;
  const lons = pts.map((p) => p.lon);
  const lats = pts.map((p) => p.lat);
  const minLon = Math.min(...lons) - PAD_KM / kx;
  const maxLon = Math.max(...lons) + PAD_KM / kx;
  const minLat = Math.min(...lats) - PAD_KM / ky;
  const maxLat = Math.max(...lats) + PAD_KM / ky;
  const n2 = GRID * GRID;
  const f: Field = {
    w: GRID,
    h: GRID,
    x0: mercX(minLon),
    x1: mercX(maxLon),
    y0: mercY(maxLat),
    y1: mercY(minLat),
    max,
    u: new Float32Array(n2),
    v: new Float32Array(n2),
    m: new Float32Array(n2),
    a: new Float32Array(n2),
  };
  const vec = pts.map((p) => {
    const to = ((p.dir + 180) * Math.PI) / 180; // the board says where it comes from; particles go the other way
    return { x: p.lon * kx, y: p.lat * ky, u: Math.sin(to) * p.mag, v: Math.cos(to) * p.mag, mag: p.mag };
  });
  for (let j = 0; j < GRID; j++) {
    const lat = latOf(f.y0 + ((f.y1 - f.y0) * (j + 0.5)) / GRID);
    for (let i = 0; i < GRID; i++) {
      const lon = lonOf(f.x0 + ((f.x1 - f.x0) * (i + 0.5)) / GRID);
      let sw = 0;
      let su = 0;
      let sv = 0;
      let sm = 0;
      let dmin = Infinity;
      for (const p of vec) {
        const dx = lon * kx - p.x;
        const dy = lat * ky - p.y;
        const d2 = dx * dx + dy * dy;
        dmin = Math.min(dmin, d2);
        const w = 1 / (d2 + 0.25);
        sw += w;
        su += w * p.u;
        sv += w * p.v;
        sm += w * p.mag;
      }
      const n = j * GRID + i;
      f.u[n] = su / sw;
      f.v[n] = sv / sw;
      f.m[n] = Math.min(1, sm / sw / max);
      f.a[n] = Math.exp(-dmin / (REACH_KM * REACH_KM));
    }
  }
  return f;
}

/** Bilinear sample at a mercator point: [u, v, m, a], or null outside the field. */
export function sample(f: Field, x: number, y: number): [number, number, number, number] | null {
  const gx = ((x - f.x0) / (f.x1 - f.x0)) * f.w - 0.5;
  const gy = ((y - f.y0) / (f.y1 - f.y0)) * f.h - 0.5;
  if (!(gx >= -0.5 && gy >= -0.5 && gx <= f.w - 0.5 && gy <= f.h - 0.5)) return null;
  const i0 = Math.max(0, Math.min(f.w - 1, Math.floor(gx)));
  const j0 = Math.max(0, Math.min(f.h - 1, Math.floor(gy)));
  const i1 = Math.min(f.w - 1, i0 + 1);
  const j1 = Math.min(f.h - 1, j0 + 1);
  const tx = Math.max(0, Math.min(1, gx - i0));
  const ty = Math.max(0, Math.min(1, gy - j0));
  const k00 = j0 * f.w + i0, k01 = j0 * f.w + i1, k10 = j1 * f.w + i0, k11 = j1 * f.w + i1;
  const w00 = (1 - tx) * (1 - ty), w01 = tx * (1 - ty), w10 = (1 - tx) * ty, w11 = tx * ty;
  const at = (a: Float32Array): number => (a[k00] ?? 0) * w00 + (a[k01] ?? 0) * w01 + (a[k10] ?? 0) * w10 + (a[k11] ?? 0) * w11;
  return [at(f.u), at(f.v), at(f.m), at(f.a)];
}

function hexRgb(hex: string): [number, number, number] {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  return m ? [parseInt(m[1] ?? 'ff', 16), parseInt(m[2] ?? 'ff', 16), parseInt(m[3] ?? 'ff', 16)] : [255, 255, 255];
}

export function rampPixels(stops: readonly string[]): Uint8Array {
  const rgb = stops.map(hexRgb);
  const out = new Uint8Array(256 * 4);
  for (let i = 0; i < 256; i++) {
    const t = (i / 255) * (rgb.length - 1);
    const k = Math.min(rgb.length - 2, Math.floor(t));
    const f = t - k;
    const lo = rgb[k] ?? [255, 255, 255];
    const hi = rgb[k + 1] ?? lo;
    const mix = (c: 0 | 1 | 2): number => Math.round(lo[c] * (1 - f) + hi[c] * f);
    out.set([mix(0), mix(1), mix(2), 255], i * 4);
  }
  return out;
}

const FIELD_VS = `attribute vec2 a_pos; uniform mat4 u_matrix; uniform vec4 u_box; varying vec2 v_uv;
void main() { v_uv = a_pos; gl_Position = u_matrix * vec4(mix(u_box.xy, u_box.zw, a_pos), 0.0, 1.0); }`;
// the box's own edge fades too, or a far-off beach leaves a visible rectangle
const FIELD_FS = `precision mediump float; uniform sampler2D u_field; uniform sampler2D u_ramp; uniform float u_opacity; varying vec2 v_uv;
void main() { vec4 f = texture2D(u_field, v_uv); vec3 c = texture2D(u_ramp, vec2(f.r, 0.5)).rgb;
 vec2 e = smoothstep(0.0, 0.15, v_uv) * smoothstep(0.0, 0.15, 1.0 - v_uv); float a = f.a * e.x * e.y * u_opacity;
 gl_FragColor = vec4(c * a, a); }`;
const LINE_VS = `attribute vec2 a_pos; attribute float a_alpha; uniform mat4 u_matrix; varying float v_alpha;
void main() { v_alpha = a_alpha; gl_Position = u_matrix * vec4(a_pos, 0.0, 1.0); }`;
const LINE_FS = `precision mediump float; uniform vec3 u_color; varying float v_alpha;
void main() { gl_FragColor = vec4(u_color * v_alpha, v_alpha); }`;

// Bound before linking so draw() needs no getAttribLocation per frame.
const A_POS = 0;
const A_ALPHA = 1;

function program(gl: WebGLRenderingContext, vs: string, fs: string): WebGLProgram {
  const shader = (type: number, src: string): WebGLShader => {
    const s = gl.createShader(type);
    if (!s) throw new Error('flow: no shader');
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(`flow shader: ${gl.getShaderInfoLog(s) ?? ''}`);
    return s;
  };
  const p = gl.createProgram();
  gl.attachShader(p, shader(gl.VERTEX_SHADER, vs));
  gl.attachShader(p, shader(gl.FRAGMENT_SHADER, fs));
  gl.bindAttribLocation(p, A_POS, 'a_pos');
  gl.bindAttribLocation(p, A_ALPHA, 'a_alpha');
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(`flow program: ${gl.getProgramInfoLog(p) ?? ''}`);
  return p;
}

function texture(gl: WebGLRenderingContext, w: number, h: number, pixels: Uint8Array): WebGLTexture {
  const t = gl.createTexture();
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

interface Particles {
  n: number;
  t: number;
  head: number;
  x: Float32Array; // n*t ring buffer of trail positions
  y: Float32Array;
  age: Float32Array;
  life: Float32Array;
  verts: Float32Array;
}

interface View {
  x0: number;
  x1: number;
  y0: number;
  y1: number;
}

export interface FlowLayer extends mapboxgl.CustomLayer {
  set(kind: string, data: Partial<Record<Kind, FlowPoint[]>>): void;
  kind(): Kind | 'off';
  field(): Field | null;
}

/** A Mapbox GL custom layer; still (reduced motion) draws each particle's whole trail once and stops. */
export function flowLayer(opts: { id: string; ramps: Record<Kind, string[]>; still: boolean }): FlowLayer {
  const { still } = opts;
  let map: mapboxgl.Map | null = null;
  let kind: Kind | 'off' = 'off';
  let data: Partial<Record<Kind, FlowPoint[]>> = {};
  let field: Field | null = null;
  let dirty = true;
  let progs: { field: WebGLProgram; line: WebGLProgram; quad: WebGLBuffer; lines: WebGLBuffer; ramps: Record<Kind, WebGLTexture> } | null = null;
  let fieldTex: WebGLTexture | null = null;
  let P: Particles | null = null;
  let last = 0;
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) map?.triggerRepaint();
  });

  const setUp = (): void => {
    field = kind === 'off' ? null : buildField(data[kind] ?? [], KINDS[kind].max);
    dirty = true;
    P = null;
    map?.triggerRepaint();
  };

  function view(f: Field, m: mapboxgl.Map): View {
    const b = m.getBounds();
    return {
      x0: Math.max(f.x0, mercX(b.getWest())),
      x1: Math.min(f.x1, mercX(b.getEast())),
      y0: Math.max(f.y0, mercY(b.getNorth())),
      y1: Math.min(f.y1, mercY(b.getSouth())),
    };
  }

  function spawn(p: Particles, k: Kind, f: Field, i: number, v: View): void {
    const K = KINDS[k];
    let x = 0;
    let y = 0;
    let ok = false;
    if (v.x1 > v.x0 && v.y1 > v.y0) {
      for (let tries = 0; tries < 8 && !ok; tries++) {
        x = v.x0 + Math.random() * (v.x1 - v.x0);
        y = v.y0 + Math.random() * (v.y1 - v.y0);
        const s = sample(f, x, y);
        ok = !!s && Math.random() < s[3];
      }
    }
    p.x.fill(x, i * p.t, (i + 1) * p.t);
    p.y.fill(y, i * p.t, (i + 1) * p.t);
    const life = K.life[0] + Math.random() * (K.life[1] - K.life[0]);
    p.life[i] = life;
    p.age[i] = ok ? 0 : life + 1; // nowhere to put it: dead, retried next frame
  }

  function step(p: Particles, k: Kind, f: Field, m: mapboxgl.Map, dt: number): void {
    const K = KINDS[k];
    const v = view(f, m);
    const perPx = 1 / (512 * 2 ** m.getZoom());
    const next = (p.head + 1) % p.t;
    for (let i = 0; i < p.n; i++) {
      const o = i * p.t;
      const x = p.x[o + p.head] ?? 0;
      const y = p.y[o + p.head] ?? 0;
      const s = sample(f, x, y);
      const age = (p.age[i] ?? 0) + dt;
      p.age[i] = age;
      if (!s || age > (p.life[i] ?? 0) || x < v.x0 || x > v.x1 || y < v.y0 || y > v.y1) {
        spawn(p, k, f, i, v);
        continue;
      }
      const mag = Math.hypot(s[0], s[1]) || 1;
      const px = K.px * (0.25 + 0.75 * s[2]) * dt * perPx;
      p.x[o + next] = x + (s[0] / mag) * px;
      p.y[o + next] = y - (s[1] / mag) * px; // mercator y grows southwards
    }
    p.head = next;
  }

  function particles(k: Kind, f: Field, m: mapboxgl.Map): Particles {
    const K = KINDS[k];
    const c = m.getCanvas();
    const n = Math.max(150, Math.min(3000, Math.round(c.clientWidth * c.clientHeight * K.density)));
    const p: Particles = {
      n,
      t: K.trail,
      head: 0,
      x: new Float32Array(n * K.trail),
      y: new Float32Array(n * K.trail),
      age: new Float32Array(n),
      life: new Float32Array(n),
      verts: new Float32Array(n * (K.trail - 1) * 6),
    };
    const v = view(f, m);
    for (let i = 0; i < n; i++) {
      spawn(p, k, f, i, v);
      if (p.age[i] === 0) p.age[i] = Math.random() * (p.life[i] ?? 0);
    }
    if (still) for (let s = 0; s < p.t; s++) step(p, k, f, m, 1);
    return p;
  }

  function buildLines(p: Particles, f: Field): number {
    const T = p.t;
    const out = p.verts;
    let n = 0;
    for (let i = 0; i < p.n; i++) {
      const o = i * T;
      const s = sample(f, p.x[o + p.head] ?? 0, p.y[o + p.head] ?? 0);
      if (!s) continue;
      const age = p.age[i] ?? 0;
      const fade = Math.min(1, age / 12, ((p.life[i] ?? 0) - age) / 12);
      const base = Math.max(0, fade) * Math.min(1, s[3] * 1.4) * (0.55 + 0.45 * s[2]);
      if (base < 0.02) continue;
      for (let k = 0; k < T - 1; k++) {
        const a = o + ((p.head - k + T) % T);
        const b = o + ((p.head - k - 1 + T) % T);
        const xa = p.x[a] ?? 0, ya = p.y[a] ?? 0, xb = p.x[b] ?? 0, yb = p.y[b] ?? 0;
        if (xa === xb && ya === yb) break;
        out[n] = xa;
        out[n + 1] = ya;
        out[n + 2] = base * (1 - k / (T - 1));
        out[n + 3] = xb;
        out[n + 4] = yb;
        out[n + 5] = base * (1 - (k + 1) / (T - 1));
        n += 6;
      }
    }
    return n / 3;
  }

  function draw(g: WebGLRenderingContext, r: NonNullable<typeof progs>, k: Kind, f: Field, m: mapboxgl.Map, matrix: number[]): void {
    if (dirty) {
      const px = new Uint8Array(f.w * f.h * 4);
      for (let n = 0; n < f.w * f.h; n++) {
        px[n * 4] = Math.round((f.m[n] ?? 0) * 255);
        px[n * 4 + 3] = Math.round((f.a[n] ?? 0) * 255);
      }
      if (fieldTex) g.deleteTexture(fieldTex);
      fieldTex = texture(g, f.w, f.h, px);
      dirty = false;
    }
    g.enable(g.BLEND);
    g.blendFunc(g.ONE, g.ONE_MINUS_SRC_ALPHA);

    g.useProgram(r.field);
    g.bindBuffer(g.ARRAY_BUFFER, r.quad);
    g.enableVertexAttribArray(A_POS);
    g.vertexAttribPointer(A_POS, 2, g.FLOAT, false, 0, 0);
    g.uniformMatrix4fv(g.getUniformLocation(r.field, 'u_matrix'), false, matrix);
    g.uniform4f(g.getUniformLocation(r.field, 'u_box'), f.x0, f.y0, f.x1, f.y1);
    g.activeTexture(g.TEXTURE0);
    g.bindTexture(g.TEXTURE_2D, fieldTex);
    g.uniform1i(g.getUniformLocation(r.field, 'u_field'), 0);
    g.activeTexture(g.TEXTURE1);
    g.bindTexture(g.TEXTURE_2D, r.ramps[k]);
    g.uniform1i(g.getUniformLocation(r.field, 'u_ramp'), 1);
    g.uniform1f(g.getUniformLocation(r.field, 'u_opacity'), 0.65);
    g.drawArrays(g.TRIANGLE_STRIP, 0, 4);
    g.disableVertexAttribArray(A_POS);

    const now = Date.now();
    if (!P) P = particles(k, f, m);
    else if (!still) step(P, k, f, m, Math.min(3, (now - last) / (1000 / 60) || 1));
    last = now;
    const count = buildLines(P, f);
    if (count) {
      g.useProgram(r.line);
      g.bindBuffer(g.ARRAY_BUFFER, r.lines);
      g.bufferData(g.ARRAY_BUFFER, P.verts.subarray(0, count * 3), g.DYNAMIC_DRAW);
      g.enableVertexAttribArray(A_POS);
      g.enableVertexAttribArray(A_ALPHA);
      g.vertexAttribPointer(A_POS, 2, g.FLOAT, false, 12, 0);
      g.vertexAttribPointer(A_ALPHA, 1, g.FLOAT, false, 12, 8);
      g.uniformMatrix4fv(g.getUniformLocation(r.line, 'u_matrix'), false, matrix);
      const [cr, cg, cb] = KINDS[k].color;
      g.uniform3f(g.getUniformLocation(r.line, 'u_color'), cr, cg, cb);
      g.drawArrays(g.LINES, 0, count);
      g.disableVertexAttribArray(A_POS);
      g.disableVertexAttribArray(A_ALPHA);
    }
    if (!still && !document.hidden) m.triggerRepaint();
  }

  return {
    id: opts.id,
    type: 'custom',
    renderingMode: '2d',
    set(k, d) {
      kind = k === 'wind' || k === 'waves' ? k : 'off';
      data = d;
      setUp();
    },
    kind: () => kind,
    field: () => field,
    onAdd(m, g) {
      map = m;
      const ramp = (k: Kind): WebGLTexture => texture(g, 256, 1, rampPixels(opts.ramps[k]));
      progs = {
        field: program(g, FIELD_VS, FIELD_FS),
        line: program(g, LINE_VS, LINE_FS),
        quad: g.createBuffer(),
        lines: g.createBuffer(),
        ramps: { wind: ramp('wind'), waves: ramp('waves') },
      };
      g.bindBuffer(g.ARRAY_BUFFER, progs.quad);
      g.bufferData(g.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), g.STATIC_DRAW);
    },
    onRemove(_m, gl) {
      if (progs) {
        gl.deleteProgram(progs.field);
        gl.deleteProgram(progs.line);
        gl.deleteBuffer(progs.quad);
        gl.deleteBuffer(progs.lines);
        gl.deleteTexture(progs.ramps.wind);
        gl.deleteTexture(progs.ramps.waves);
        if (fieldTex) gl.deleteTexture(fieldTex);
      }
      progs = null;
      fieldTex = null;
      dirty = true;
      P = null;
      map = null;
    },
    render(g, matrix) {
      if (field && progs && map && kind !== 'off') draw(g, progs, kind, field, map, matrix);
    },
  };
}
