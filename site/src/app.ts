/** The map page (MIP-0005 §5.3). */
import {
  type Area,
  areaCode,
  band,
  type Beach,
  type Board,
  hourEntry,
  hoursOf,
  isPast,
  type Latest,
  type Shown,
  ranked,
  SCHEMAS,
  shown,
  waterBand,
} from './board.ts';
import { closest, initChrome, onLang, param, setParam } from './chrome.ts';
import { type FlowLayer, flowLayer, type FlowPoint } from './flow.ts';
import { NINO34, RASTERS, rasterDay, tileUrl } from './gibs.ts';
import { t } from './i18n.ts';
import { waveSound } from './sound.ts';
import {
  aspectsHtml,
  cardHtml,
  daysHtml,
  dotSvg,
  esc,
  footerHtml,
  listHtml,
  trailTipHtml,
  tx,
  waterPointTipHtml,
} from './view.ts';

initChrome();

const DEFAULT_STYLE = 'mapbox://styles/mapbox/outdoors-v12';

function byId(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`index.html has no #${id}`);
  return node;
}
const el = {
  area: byId('area') as HTMLSelectElement,
  days: byId('days'),
  near: byId('near'),
  sound: byId('sound'),
  toggleList: byId('toggle-list'),
  hourbar: byId('hourbar'),
  hour: byId('hour') as HTMLInputElement,
  hourLabel: byId('hour-label'),
  list: byId('list'),
  card: byId('card'),
  footer: byId('footer'),
  flow: byId('flow'),
  keys: byId('flowkeys'),
  mapNote: byId('map-note'),
  map: byId('map'),
};

interface Pin {
  node: HTMLElement;
  marker: mapboxgl.Marker;
  tip: mapboxgl.Popup;
}

const state = {
  areas: [] as Area[],
  area: null as Area | null,
  latest: null as Latest | null,
  day: null as string | null,
  board: null as Board | null,
  hours: [] as string[],
  hourIndex: -1, // -1 = each beach at its own best hour
  selected: null as string | null, // beach name
  here: null as { lat: number; lon: number } | null, // after "near me"
  layer: 'off', // 'off' or the data-layer of an enabled rail button
  beaches: true,
  trails: true,
  map: null as mapboxgl.Map | null,
  mapFailed: false,
  mapNoteKey: null as string | null,
  ready: false,
  flow: null as FlowLayer | null,
  markers: [] as Pin[],
  waterPins: [] as Pin[],
  herePin: null as Pin | null,
  bounds: null as mapboxgl.Bounds | null,
  fitted: false,
  zoomedOut: false,
  rasterId: null as string | null,
};

// A live declaration: one lookup serves every marker and trail.
const rootStyle = getComputedStyle(document.documentElement);
const css = (name: string): string => rootStyle.getPropertyValue(name).trim();
const reducedMotion = (): boolean => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const hourAt = (): string | null => state.hours[state.hourIndex] ?? null;
const shownOf = (b: Beach): Shown | null => shown(b, hourAt());
const beachByName = (name: string | null): Beach | null => state.board?.beaches.find((b) => b.name === name) ?? null;
const status = (text: string): void => {
  const s = document.getElementById('status');
  if (s) s.textContent = text;
};

async function fetchJson<T>(path: string): Promise<T> {
  const r = await fetch(path, { cache: 'no-cache' });
  if (!r.ok) throw new Error(`${r.status} ${path}`);
  return (await r.json()) as T;
}

async function loadAreas(): Promise<void> {
  const j = await fetchJson<{ areas?: Area[] }>('data/areas.json');
  state.areas = j.areas ?? [];
  const wanted = state.areas.find((a) => a.id === param('area')) ?? state.areas[0];
  if (!wanted) throw new Error(t('fail.no_areas'));
  el.area.innerHTML = state.areas
    .map((a) => `<option value="${esc(a.id)}" title="${esc(a.name)}" aria-label="${esc(a.name)}">${esc(areaCode(a))}</option>`)
    .join('');
  el.area.value = wanted.id;
  await selectArea(wanted);
}

async function selectArea(area: Area): Promise<void> {
  state.area = area;
  setParam('area', area.id);
  el.area.title = area.name;
  ensureMap(area);
  status(t('status.loading_named', { name: area.name }));
  const latest = await fetchJson<Latest>(`data/${area.id}/latest.json`);
  state.latest = latest;
  renderDays();
  const pick = latest.days.find((d) => d.day === param('day')) ?? latest.days.at(-1);
  if (pick) await selectDay(pick);
}

// Separate so a language flip relabels the days without refetching latest.json.
function renderDays(): void {
  if (state.latest) el.days.innerHTML = daysHtml(state.latest.days, state.day);
}

async function selectDay(d: { day: string; file: string }): Promise<void> {
  if (!state.area) return;
  state.day = d.day;
  setParam('day', d.day);
  for (const b of el.days.children) b.classList.toggle('on', (b as HTMLElement).dataset.day === d.day);
  status(t('status.loading_named', { name: d.day }));
  const board = await fetchJson<Board>(`data/${state.area.id}/${d.file}`);
  if (!SCHEMAS.includes(board.schema)) throw new Error(t('fail.schema', { got: String(board.schema), want: SCHEMAS.join(', ') }));
  state.board = board;
  state.hours = hoursOf(board);
  el.hour.max = String(state.hours.length - 1);
  el.hour.value = '-1';
  state.hourIndex = -1;
  el.hourbar.hidden = state.hours.length === 0;
  const beach = param('beach');
  if (beach && !state.selected && beachByName(beach)) state.selected = beach;
  renderWaterPoints();
  render();
}

function firstSymbolLayer(map: mapboxgl.Map): string | undefined {
  return map.getStyle()?.layers?.find((l) => l.type === 'symbol')?.id;
}

// The Mapbox GL licence allows it only with a Mapbox account, so with no token there is no map, and the list
// carries the page.
function ensureMap(area: Area): void {
  if (!state.map && !state.mapFailed) {
    const gl = window.mapboxgl;
    const config = window.MAROLA_MAPBOX ?? {};
    if (!gl || !config.token) {
      state.mapFailed = true;
      mapNote('map.no_token');
    } else {
      try {
        state.map = createMap(gl, config.token, config.style || DEFAULT_STYLE, area);
      } catch (e) {
        console.error(e);
        state.mapFailed = true;
        mapNote('map.failed');
      }
    }
  }
  state.map?.jumpTo({ center: [area.lon, area.lat], zoom: 10 });
}

function createMap(gl: mapboxgl.Api, token: string, style: string, area: Area): mapboxgl.Map {
  gl.accessToken = token;
  // the CSP build: the worker is a same-origin file, not a blob: (script-src 'self'), keyed to the bundle's
  // version so a cached old worker never pairs with a new bundle
  gl.workerUrl = `vendor/mapbox-gl-csp-worker.js?v=${gl.version}`;
  const map = new gl.Map({
    container: 'map',
    style,
    projection: 'mercator',
    center: [area.lon, area.lat],
    zoom: 10,
    minZoom: 3,
    maxZoom: 17,
    attributionControl: true,
    collectResourceTiming: false,
    pitchWithRotate: false,
    dragRotate: false,
  });
  map.touchZoomRotate.disableRotation();
  // the hour bar and footer fill in after the map is made and change #map's height
  if (typeof ResizeObserver === 'function') new ResizeObserver(() => map.resize()).observe(el.map);
  map.addControl(new gl.NavigationControl({ showCompass: false }), 'top-left');
  map.on('click', (e) => {
    // a click on a marker reaches the map too
    if ((e.originalEvent?.target as Element | null)?.closest('.mapboxgl-marker')) return;
    if (state.selected) closeCard();
  });
  map.on('error', (e) => {
    console.error(e.error ?? e);
    // a refused token or a missing style never fires load: say so instead of a blank map
    const s = e.error?.status;
    if (!state.ready && !state.mapFailed && (s === 401 || s === 403 || s === 404)) {
      state.mapFailed = true;
      mapNote('map.failed');
    }
  });
  // Mapbox rebuilds its own layers after a lost GPU context, not a custom layer's GL state
  map.on('webglcontextrestored', () => {
    if (!state.flow || !map.getLayer(state.flow.id)) return;
    map.removeLayer(state.flow.id);
    map.addLayer(state.flow, firstSymbolLayer(map));
  });
  map.on('load', () => {
    state.ready = true;
    addTrailLayer(gl, map);
    const ramp = (name: string): string[] => [0, 1, 2, 3, 4, 5].map((i) => css(`--flow-${name}-${i}`));
    state.flow = flowLayer({ id: 'marola-flow', still: reducedMotion(), ramps: { wind: ramp('wind'), waves: ramp('wave') } });
    // under the labels, so place names stay readable over the particles
    map.addLayer(state.flow, firstSymbolLayer(map));
    // coastline over the field; only Mapbox's own styles have the `composite` source
    if (map.getSource('composite'))
      map.addLayer(
        { id: 'marola-coast', type: 'line', source: 'composite', 'source-layer': 'water', paint: { 'line-color': 'rgba(17,24,32,0.35)', 'line-width': 0.7 } },
        firstSymbolLayer(map),
      );
    if (state.board) {
      renderTrails();
      renderLayers();
    }
  });
  return map;
}

function mapNote(key: string): void {
  state.mapNoteKey = key;
  el.mapNote.textContent = t(key);
  el.mapNote.hidden = false;
  el.flow.hidden = true;
  setListOpen(true);
}

function setListOpen(open: boolean): void {
  el.list.hidden = !open;
  el.toggleList.setAttribute('aria-expanded', String(open));
}

/** A popup open while the pin has hover or keyboard focus. */
function pin(cls: string, html: string, label: string | null, at: mapboxgl.LngLatLike, tipHtml: string, tipCls: string, offset: number): Pin | null {
  const map = state.map;
  const gl = window.mapboxgl;
  if (!map || !gl) return null;
  const node = document.createElement('div');
  node.className = cls;
  node.innerHTML = html;
  if (label) {
    node.setAttribute('role', 'button');
    node.setAttribute('tabindex', '0');
    node.setAttribute('aria-label', label);
  }
  const marker = new gl.Marker({ element: node, anchor: 'center' }).setLngLat(at).addTo(map);
  const tip = new gl.Popup({ closeButton: false, closeOnClick: false, focusAfterOpen: false, className: tipCls, offset, maxWidth: 'none' })
    .setLngLat(at)
    .setHTML(tipHtml);
  const show = (): void => void tip.addTo(map);
  const hide = (): void => void tip.remove();
  node.addEventListener('mouseenter', show);
  node.addEventListener('mouseleave', hide);
  node.addEventListener('focus', show);
  node.addEventListener('blur', hide);
  return { node, marker, tip };
}

function unpin(pins: readonly Pin[]): void {
  for (const p of pins) {
    p.marker.remove();
    p.tip.remove();
  }
}

// Trails (MIP-0030): one GeoJSON line layer, not one per trail.
function addTrailLayer(gl: mapboxgl.Api, map: mapboxgl.Map): void {
  map.addSource('trails', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
  map.addLayer({
    id: 'trails',
    type: 'line',
    source: 'trails',
    layout: { 'line-cap': 'round' },
    paint: { 'line-color': ['get', 'color'], 'line-width': 3, 'line-opacity': 0.85, 'line-dasharray': [1.5, 1.5] },
  });
  const tip = new gl.Popup({ closeButton: false, closeOnClick: false, offset: 8, maxWidth: 'none' });
  map.on('mousemove', 'trails', (e) => {
    const html = e.features?.[0]?.properties.tip;
    if (!html) return;
    map.getCanvas().style.cursor = 'default';
    tip.setLngLat(e.lngLat).setHTML(html).addTo(map);
  });
  map.on('mouseleave', 'trails', () => tip.remove());
}

function trailColour(difficulty: string | null): string {
  if (difficulty === 'hiking') return css('--c70');
  if (difficulty === 'mountain_hiking') return css('--c40');
  return css('--cna');
}

function renderTrails(): void {
  if (!state.ready || !state.map || !state.board) return;
  const features = (state.board.trails ?? [])
    .filter((trail) => trail.geometry.length >= 2)
    .map((trail) => ({
      type: 'Feature',
      properties: { color: trailColour(trail.difficulty), tip: trailTipHtml(trail) },
      geometry: { type: 'LineString', coordinates: trail.geometry.map(([lat, lon]) => [lon, lat]) },
    }));
  state.map.getSource('trails')?.setData({ type: 'FeatureCollection', features });
}

/** One point per beach at the hour on show; directions are the board's (best hour) ones. */
function flowPoints(board: Board): Record<'wind' | 'waves', FlowPoint[]> {
  const wind: FlowPoint[] = [];
  const waves: FlowPoint[] = [];
  for (const b of board.beaches) {
    const e = hourEntry(b, shownOf(b));
    if (!e) continue;
    wind.push({ lon: b.lon, lat: b.lat, mag: e.wind_kmh, dir: b.sea.wind_dir_deg });
    waves.push({ lon: b.lon, lat: b.lat, mag: e.wave_m, dir: b.sea.wave_dir_deg });
  }
  return { wind, waves };
}

function renderLayers(): void {
  for (const b of el.flow.querySelectorAll<HTMLElement>('button[data-layer]')) b.setAttribute('aria-pressed', String(b.dataset.layer === state.layer));
  for (const b of el.flow.querySelectorAll<HTMLElement>('button[data-toggle]'))
    b.setAttribute('aria-pressed', String(b.dataset.toggle === 'trails' ? state.trails : state.beaches));
  for (const k of el.keys.querySelectorAll<HTMLElement>('[data-key]')) k.hidden = k.dataset.key !== state.layer;
  el.map.classList.toggle('layer-water', state.layer === 'water');
  el.map.classList.toggle('no-beaches', !state.beaches);
  if (state.map && state.ready && state.map.getLayer('trails')) state.map.setLayoutProperty('trails', 'visibility', state.trails ? 'visible' : 'none');
  renderRaster();
  if (!state.flow || !state.board) return;
  state.flow.set(state.layer, flowPoints(state.board));
}

function renderRaster(): void {
  const today = state.board?.today ?? new Date().toISOString().slice(0, 10);
  for (const w of el.keys.querySelectorAll<HTMLElement>('[data-when]')) {
    const k = RASTERS[w.dataset.when ?? ''];
    w.textContent = k ? rasterDay(k, today) : '';
  }
  const map = state.map;
  if (!map || !state.ready) return;
  const r = RASTERS[state.layer];
  const id = r ? `${r.layer}/${rasterDay(r, today)}` : null;
  if (state.rasterId !== id) {
    if (state.rasterId) {
      map.removeLayer('marola-raster');
      map.removeSource('marola-raster');
    }
    state.rasterId = id;
    if (r) {
      map.addSource('marola-raster', {
        type: 'raster',
        tileSize: 256,
        maxzoom: r.maxzoom,
        attribution: '<a href="https://www.earthdata.nasa.gov/gibs">NASA GIBS</a>',
        tiles: [tileUrl(r, today)],
      });
      map.addLayer(
        { id: 'marola-raster', type: 'raster', source: 'marola-raster', paint: { 'raster-opacity': r.opacity } },
        map.getLayer('marola-coast') ? 'marola-coast' : firstSymbolLayer(map),
      );
    }
  }
  const nino = state.layer === 'elnino';
  if (nino && !map.getSource('nino34')) {
    map.addSource('nino34', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: NINO34 } } });
    map.addLayer({ id: 'nino34', type: 'line', source: 'nino34', paint: { 'line-color': '#ffffff', 'line-width': 1.5, 'line-dasharray': [2, 2] } });
  }
  if (map.getLayer('nino34')) map.setLayoutProperty('nino34', 'visibility', nino ? 'visible' : 'none');
  if (nino !== state.zoomedOut) {
    state.zoomedOut = nino;
    const duration = reducedMotion() ? 0 : 1200;
    // the Pacific needs zoom ~1 on a phone, below the area's minZoom
    map.setMinZoom(nino ? 0 : 3);
    if (nino)
      map.fitBounds(
        [
          [-180, -30],
          [-60, 25],
        ],
        { padding: 20, duration },
      );
    else if (state.bounds) map.fitBounds(state.bounds, { padding: 40, duration, maxZoom: 13 });
  }
}

function renderMarkers(board: Board): void {
  unpin(state.markers);
  state.markers = [];
  renderTrails();
  for (const beach of board.beaches) {
    const s = shownOf(beach);
    const selected = state.selected === beach.name;
    const past = !!s && isPast(board, s.h);
    const score = s ? s.score : null;
    const b = band(score, beach.water.unfit);
    // No `title`: the browser would draw a native tooltip on top of the popup.
    const m = pin(
      `wave${selected ? ' selected' : ''}${past ? ' past' : ''}`,
      dotSvg(css(`--${b}`), selected, score, b === 'c40'),
      beach.name,
      [beach.lon, beach.lat],
      aspectsHtml(beach, s),
      'aspects',
      selected ? 18 : 10,
    );
    if (!m) continue;
    m.node.addEventListener('click', (ev) => {
      ev.stopPropagation();
      select(beach.name, false);
    });
    m.node.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        select(beach.name, false);
      }
    });
    state.markers.push(m);
  }
  if (board.beaches.length) {
    const lons = board.beaches.map((b) => b.lon);
    const lats = board.beaches.map((b) => b.lat);
    state.bounds = [
      [Math.min(...lons), Math.min(...lats)],
      [Math.max(...lons), Math.max(...lats)],
    ];
    if (!state.fitted && !state.zoomedOut) {
      state.map?.fitBounds(state.bounds, { padding: 40, duration: 0, maxZoom: 13 });
      state.fitted = true;
    }
  }
}

/** The water layer shows every beach's sampling points; the others only the selected beach's. */
function renderWaterPoints(): void {
  unpin(state.waterPins);
  state.waterPins = [];
  const selected = beachByName(state.selected);
  const beaches = state.layer === 'water' && state.board ? state.board.beaches : selected ? [selected] : [];
  for (const p of beaches.flatMap((b) => b.water.points)) {
    const m = pin(`wpoint ${waterBand(p.condition)}`, '', p.point, [p.lon, p.lat], waterPointTipHtml(p), '', 8);
    if (m) state.waterPins.push(m);
  }
}

function render(): void {
  const board = state.board;
  if (!board || !state.area) return;
  if (state.map) renderMarkers(board);
  const h = hourAt();
  el.hourLabel.textContent = h === null ? t('hour.best') : t('hour.at', { h, past: isPast(board, h) ? 'yes' : 'no' });
  el.list.innerHTML = listHtml(ranked(board.beaches, (b) => shownOf(b)?.score ?? null, state.here).map((r) => ({ ...r, shown: shownOf(r.beach) })));
  el.footer.innerHTML = footerHtml(board, state.area.name);
  renderLayers();
  if (state.selected) renderCard();
}

function renderCard(): void {
  const b = beachByName(state.selected);
  if (!b || !state.board) {
    el.card.hidden = true;
    return;
  }
  el.card.innerHTML = cardHtml(state.board, b, shownOf(b));
  el.card.hidden = false;
  el.card.querySelector('.close')?.addEventListener('click', closeCard);
}

function select(name: string, pan: boolean): void {
  state.selected = name;
  setParam('beach', name);
  const b = beachByName(name);
  if (b && pan) state.map?.panTo([b.lon, b.lat]);
  renderWaterPoints();
  render();
}

function closeCard(): void {
  state.selected = null;
  el.card.hidden = true;
  setParam('beach', null);
  renderWaterPoints();
  render();
}

function fail(err: unknown): void {
  const msg = err instanceof Error ? err.message : String(err);
  // fetchJson's error is "<status> <path>"; only a missing board JSON means "not built yet".
  status(t('fail.load', { error: msg, hint: /^404 data\/.*\.json$/.test(msg) ? 'yes' : 'no' }));
  console.error(err);
}

el.area.addEventListener('change', () => {
  const area = state.areas.find((a) => a.id === el.area.value);
  if (!area) return;
  state.fitted = false;
  state.selected = null;
  el.card.hidden = true;
  setParam('beach', null);
  selectArea(area).catch(fail);
});
el.days.addEventListener('click', (e) => {
  const btn = closest(e.target, 'button');
  if (btn?.dataset.day && btn.dataset.file) selectDay({ day: btn.dataset.day, file: btn.dataset.file }).catch(fail);
});
el.hour.addEventListener('input', () => {
  state.hourIndex = parseInt(el.hour.value, 10);
  render();
});
el.flow.addEventListener('click', (e) => {
  const btn = closest(e.target, 'button') as HTMLButtonElement | null;
  if (!btn || btn.disabled) return;
  const toggle = btn.dataset.toggle;
  if (toggle === 'beaches' || toggle === 'trails') {
    state[toggle] = !state[toggle];
    setParam(toggle, state[toggle] ? '1' : '0');
  } else if (btn.dataset.layer) {
    state.layer = btn.dataset.layer === state.layer ? 'off' : btn.dataset.layer;
    setParam('layer', state.layer);
  } else return;
  renderLayers();
  if (state.board) renderWaterPoints();
});
el.toggleList.addEventListener('click', () => {
  setListOpen(el.list.hidden === true);
});
el.list.addEventListener('click', (e) => {
  const name = closest(e.target, 'li')?.dataset.name;
  if (name) select(name, true);
});
el.near.addEventListener('click', () => {
  if (state.here) {
    state.here = null;
    if (state.herePin) unpin([state.herePin]);
    state.herePin = null;
    el.near.setAttribute('aria-pressed', 'false');
    render();
    return;
  }
  if (!('geolocation' in navigator)) {
    alert(t('near.unsupported'));
    return;
  }
  navigator.geolocation.getCurrentPosition(
    (pos) => {
      const here = { lat: pos.coords.latitude, lon: pos.coords.longitude };
      state.here = here;
      el.near.setAttribute('aria-pressed', 'true');
      setListOpen(true);
      if (state.herePin) unpin([state.herePin]);
      state.herePin = pin('here', '', null, [here.lon, here.lat], tx('near.you'), '', 8);
      render();
    },
    () => {
      alert(t('near.denied'));
    },
  );
});
waveSound(el.sound);

// chrome.ts has relabelled the static text; redraw what the app built, without a fetch.
onLang(() => {
  renderDays();
  if (!state.board) return;
  render();
  renderWaterPoints();
  state.herePin?.tip.setHTML(tx('near.you'));
  if (state.mapNoteKey) el.mapNote.textContent = t(state.mapNoteKey);
});

// the rail's markup says which layers are built: a disabled button ("em breve") is never shown, even from a ?layer= link
const enabled = (attr: 'layer' | 'toggle', value: string | null): boolean =>
  [...el.flow.querySelectorAll<HTMLButtonElement>(`button[data-${attr}]`)].some((b) => b.dataset[attr] === value && !b.disabled);
const wantedLayer = param('layer');
if (wantedLayer && enabled('layer', wantedLayer)) state.layer = wantedLayer;
if (param('beaches') === '0') state.beaches = false;
if (param('trails') === '0' || !enabled('toggle', 'trails')) state.trails = false;

loadAreas().catch(fail);
