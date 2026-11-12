// Why this file exists: MapLibre GL JS, the browser APIs and WebGL have no Elm
// bindings, so every imperative call lives here behind a few string-in, string-out
// functions. Elm sends plain JSON through ports.js; DOM for markers and popups is built from a JSON
// tree with createElement/createTextNode only (never HTML strings), which keeps the
// strict CSP intact. Work requested before the style has loaded is queued per kind
// (latest wins) because MapLibre rejects source/layer calls on an unloaded style.
import { createFlowLayer } from "./flow_layer_ffi.mjs";

const PACIFIC = [[-170, -5], [-120, 5]];
let lib = null, map = null, loaded = false, dead = false, emitFn = () => {};
const pending = new Map();
const parts = {}; // per part: last JSON text and live markers
const trails = { data: null, visible: true, selected: -1 };
let trailPopup = null, flow = null;

const queue = (kind, fn) => (loaded ? fn() : pending.set(kind, fn));
const fail = (m) => { if (!loaded) emitFn("error", String(m)); };

function flush() {
  // minzoom first: the pacific fit needs minZoom already lowered.
  const entries = [...pending].sort(([a], [b]) => (b === "minzoom") - (a === "minzoom"));
  pending.clear();
  for (const [, fn] of entries) fn();
}

// Tree format: string = text node, object = element (namespaced when ns is set).
function build(d) {
  if (typeof d === "string") return document.createTextNode(d);
  const el = d.ns ? document.createElementNS(d.ns, d.tag) : document.createElement(d.tag);
  for (const [k, v] of Object.entries(d.attrs || {})) {
    if (k !== "style" && !k.startsWith("on")) el.setAttribute(k, v);
  }
  for (const c of d.children || []) el.appendChild(build(c));
  return el;
}

async function mount(config) {
  let el = null;
  for (let i = 0; i < 120 && !(el = document.getElementById("map")); i++) {
    await new Promise((r) => requestAnimationFrame(r));
  }
  if (!el) return fail("map container missing");
  const [maplibre, pmtiles] = await Promise.all([import(config.module), import(config.pmtiles)]);
  lib = maplibre;
  lib.setWorkerUrl(config.worker);
  // The tiles file is deep only around each area (scripts/basemap_extract.sh). A missing tile must be
  // an error, not an empty tile: MapLibre then keeps drawing the nearest ancestor it has.
  lib.addProtocol("pmtiles", new pmtiles.Protocol({ errorOnMissingTile: true }).tile);
  const expected = (e) => e.tile && e.error && e.error.message === "Tile not found.";
  map = new lib.Map({
    container: el, style: config.style, center: [config.lon, config.lat],
    zoom: config.zoom, minZoom: config.minZoom, maxZoom: config.maxZoom,
    attributionControl: false, renderWorldCopies: false,
  });
  map.addControl(new lib.AttributionControl({ compact: true, customAttribution: config.attributions }));
  map.addControl(new lib.NavigationControl(), 'top-left');
  // A source that failed as a whole (no tiles file) still lets MapLibre fire "load": the map stays failed.
  map.on("error", (e) => { if (expected(e)) return; dead = dead || (!!e.sourceId && !e.tile); fail((e.error && e.error.message) || "map error"); });
  map.on("click", onMapClick);
  map.on("load", () => { if (dead) return; loaded = true; emitFn("ready", ""); flush(); });
}

export function initMap(configJson, emit) {
  emitFn = emit;
  mount(JSON.parse(configJson)).catch((e) => fail(e && e.message ? e.message : e));
}

// One handler decides between trail and empty-map clicks; marker clicks stop propagation.
function onMapClick(e) {
  const hit = map.getLayer("trails-hit") && map.queryRenderedFeatures(e.point, { layers: ["trails-hit"] })[0];
  if (hit) emitFn("trail", String(hit.properties.id));
  else emitFn("click", "");
}

function popupFor(m, node) {
  const tip = build(m.tip);
  let popup = null;
  const show = () => {
    if (popup) return;
    const opts = { closeButton: false, closeOnClick: false, offset: m.offset };
    if (m.tip_class) opts.className = m.tip_class;
    popup = new lib.Popup(opts).setLngLat([m.lon, m.lat]).setDOMContent(tip).addTo(map);
  };
  const hide = () => { if (popup) popup.remove(); popup = null; };
  for (const [ev, fn] of [["pointerenter", show], ["pointerleave", hide], ["focus", show], ["blur", hide]]) {
    node.addEventListener(ev, fn);
  }
  return hide;
}

function makeMarker(m) {
  const node = build(m.node);
  const hide = popupFor(m, node);
  if (m.click !== null) {
    node.setAttribute("tabindex", "0");
    node.setAttribute("role", "button");
    if (m.label) node.setAttribute("aria-label", m.label);
    const go = (e) => { e.stopPropagation(); emitFn(m.click, m.key); };
    node.addEventListener("click", go);
    node.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); go(e); }
    });
  }
  const marker = new lib.Marker({ element: node, anchor: "center" }).setLngLat([m.lon, m.lat]).addTo(map);
  return { remove: () => { hide(); marker.remove(); } };
}

function redraw(part, list) {
  const text = JSON.stringify(list);
  if (parts[part] && parts[part].text === text) return;
  if (parts[part]) parts[part].items.forEach((i) => i.remove());
  parts[part] = { text, items: list.map(makeMarker) };
}

function dropLayer(id) {
  if (map.getLayer(id)) map.removeLayer(id);
  if (map.getSource(id)) map.removeSource(id);
}

function setRaster(r) {
  const cur = parts.raster;
  if (cur && r && cur.id === r.id) return map.setPaintProperty("gibs", "raster-opacity", r.opacity);
  dropLayer("gibs");
  parts.raster = r;
  if (!r) return;
  map.addSource("gibs", {
    type: "raster", tiles: Array.isArray(r.tiles) ? r.tiles : [r.tiles], tileSize: 256,
    maxzoom: r.maxzoom, attribution: r.attribution,
  });
  const symbol = map.getStyle().layers.find((l) => l.type === "symbol"); // keep labels above the imagery
  map.addLayer({ id: "gibs", type: "raster", source: "gibs", paint: { "raster-opacity": r.opacity } }, symbol && symbol.id);
}

function setNino(coords) {
  if (!coords) return dropLayer("nino34");
  const ring = coords.slice();
  const a = ring[0], b = ring[ring.length - 1];
  if (a && (a[0] !== b[0] || a[1] !== b[1])) ring.push(a);
  const data = { type: "Feature", properties: {}, geometry: { type: "LineString", coordinates: ring } };
  if (map.getSource("nino34")) return map.getSource("nino34").setData(data);
  map.addSource("nino34", { type: "geojson", data });
  map.addLayer({ id: "nino34", type: "line", source: "nino34", paint: { "line-color": "#1d2733", "line-width": 2 } });
}

export function syncMap(json) {
  const s = JSON.parse(json);
  trails.visible = s.trails.visible;
  trails.selected = s.trails.selected;
  queue("sync", () => {
    redraw("markers", s.markers);
    redraw("points", s.points);
    redraw("here", s.here);
    setRaster(s.raster);
    setNino(s.nino);
  });
  queue("trails", applyTrails);
}

function trailLayers() {
  const sel = ["==", ["get", "id"], trails.selected];
  const round = { "line-cap": "round", "line-join": "round" };
  return [
    { id: "trails-line", layout: round, paint: { "line-color": ["get", "color"], "line-width": 3 } },
    { id: "trails-hit", layout: round, paint: { "line-color": "#000000", "line-opacity": 0, "line-width": 14 } },
    { id: "trails-selected-casing", layout: round, filter: sel, paint: { "line-color": "#ffffff", "line-width": 8 } },
    { id: "trails-selected", layout: round, filter: sel, paint: { "line-color": "#1d2733", "line-width": 4 } },
  ];
}

function hoverTrail(e) {
  const f = e.features && e.features[0];
  if (!f) return;
  if (!trailPopup) trailPopup = new lib.Popup({ closeButton: false, closeOnClick: false, offset: 8 });
  trailPopup.setLngLat(e.lngLat).setDOMContent(build(JSON.parse(f.properties.tip))).addTo(map);
  map.getCanvas().style.cursor = "pointer";
}

function leaveTrail() {
  if (trailPopup) trailPopup.remove();
  map.getCanvas().style.cursor = "";
}

function applyTrails() {
  if (!trails.data) return;
  if (map.getSource("trails")) {
    map.getSource("trails").setData(trails.data);
  } else {
    map.addSource("trails", { type: "geojson", data: trails.data, promoteId: "id" });
    for (const l of trailLayers()) map.addLayer({ ...l, type: "line", source: "trails" });
    map.on("mousemove", "trails-hit", hoverTrail);
    map.on("mouseleave", "trails-hit", leaveTrail);
  }
  for (const l of trailLayers()) {
    map.setLayoutProperty(l.id, "visibility", trails.visible ? "visible" : "none");
    if (l.filter) map.setFilter(l.id, l.filter);
  }
  if (!trails.visible) leaveTrail();
}

export function setTrails(geojson) {
  trails.data = JSON.parse(geojson);
  queue("trails", applyTrails);
}

export function setFlow(json) {
  const field = JSON.parse(json);
  queue("flow", () => {
    if (!field) { dropLayer("flow"); flow = null; return; }
    if (flow && map.getLayer("flow")) { flow.setField(field); map.triggerRepaint(); return; }
    flow = createFlowLayer("flow");
    flow.setField(field);
    map.addLayer(flow, map.getLayer("trails-line") ? "trails-line" : undefined);
  });
}

export function camera(json) {
  const c = JSON.parse(json);
  queue(c.kind === "minzoom" ? "minzoom" : "camera", () => {
    if (c.kind === "jump") map.jumpTo({ center: [c.lon, c.lat], zoom: c.zoom });
    else if (c.kind === "pan") map.panTo([c.lon, c.lat]);
    else if (c.kind === "minzoom") map.setMinZoom(c.zoom);
    else if (c.kind === "pacific") map.fitBounds(PACIFIC, { padding: 40, animate: !c.instant });
    else map.fitBounds([[c.west, c.south], [c.east, c.north]], { padding: c.padding, maxZoom: c.max_zoom, animate: !c.instant });
  });
}

export function locate(onOk, onErr) {
  if (!navigator.geolocation) return onErr("geolocation unavailable");
  navigator.geolocation.getCurrentPosition(
    (p) => onOk(p.coords.latitude, p.coords.longitude),
    (e) => onErr(String(e.message || e.code)),
    { timeout: 10000, maximumAge: 60000 },
  );
}

export const storeLanguage = (tag) => { try { localStorage.setItem("marola.lang", tag); } catch (_) { /* private mode */ } };
export const readLanguage = () => { try { return localStorage.getItem("marola.lang") || ""; } catch (_) { return ""; } };
export const replaceUrl = (path, query) => history.replaceState(null, "", path + (query ? "?" + query : ""));
export const alertText = (text) => window.alert(text);
export const setDocument = (language, title) => { document.documentElement.lang = language; document.title = title; };
export const focusId = (id) => { const el = document.getElementById(id); if (el) el.focus(); };

export const readEnv = () => JSON.stringify({
  path: location.pathname, search: location.search, languages: [...(navigator.languages || [])],
  reduced_motion: matchMedia("(prefers-reduced-motion: reduce)").matches,
});
