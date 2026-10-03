/** marola map — MIP-0005 §5.3. */
(function () {
  'use strict';

  var SCHEMAS = [1, 2]; // 2 adds note_codes (MIP-0054 task 3); anything else is a board newer than this page
  var SOURCE_LINKS = {
    'OpenStreetMap/Overpass': 'https://www.openstreetmap.org/copyright',
    'Open-Meteo': 'https://open-meteo.com/',
    'IMA/SC': 'https://balneabilidade.ima.sc.gov.br/'
  };
  var REPO = 'https://github.com/marola-dev/marola';

  var $ = function (id) { return document.getElementById(id); };
  var el = {
    area: $('area'), days: $('days'), near: $('near'), sound: $('sound'), toggleList: $('toggle-list'),
    hourbar: $('hourbar'), hour: $('hour'), hourLabel: $('hour-label'),
    list: $('list'), card: $('card'), footer: $('footer'), status: $('status'),
    flow: $('flow'), keys: $('flowkeys'), mapNote: $('map-note'), map: $('map')
  };

  var state = {
    areas: [], area: null, latest: null, board: null,
    hours: [],          // union of "HH:00" across beaches, sorted — the slider's stops
    hourIndex: -1,      // -1 = each beach at its own best hour
    selected: null,     // beach name
    here: null,         // {lat, lon} after "near me"
    markers: {}, map: null, flow: null, ready: false,
    waterPointMarkers: [],
    layer: 'off',       // the map layer: 'off' or one of LAYERS whose button is enabled
    beaches: true,      // the beach dots and the coastal trails: toggles over any layer
    trails: true
  };
  // site.yml writes mapbox-config.js from the repo's MAPBOX_PUBLIC_TOKEN at deploy (AGENTS.md).
  var MAPBOX = window.MAROLA_MAPBOX || {};
  var DEFAULT_STYLE = 'mapbox://styles/mapbox/outdoors-v12';

  // --- helpers -------------------------------------------------------------------------------.
  var I = window.marolaI18n, t = I.t;
  function esc(s) { return String(s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  /** t() for text with plain-text args, escaped whole; markup args go through bare t() pre-escaped. */
  function tx(key, args) { return esc(t(key, args)); }
  var formats = {};
  function num(n, digits) {
    var k = I.locale() + digits;
    if (!formats[k]) formats[k] = new Intl.NumberFormat(I.locale(), { minimumFractionDigits: digits, maximumFractionDigits: digits });
    return formats[k].format(n);
  }
  // A no-break space keeps "6 s" together when a tooltip cell wraps.
  function fmt(n, unit, digits) {
    if (n === null || n === undefined) return t('common.na');
    return num(n, digits === undefined ? 1 : digits) + (unit || '').replace(' ', '\u00a0');
  }
  function shortDate(iso) {
    return new Intl.DateTimeFormat(I.locale(), { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(iso + 'T00:00:00Z'));
  }
  /** A wire enum through the catalog (wind.*, lvl.*, dir.*); a value with no key passes through. */
  function word(prefix, v) {
    var key = prefix + String(v).toLowerCase(), out = t(key);
    return out === key ? String(v) : out;
  }
  function colour(score, unfit) {
    if (score === null || score === undefined) return getCss('--cna');
    if (unfit || score <= 0) return getCss('--c0');
    if (score >= 70) return getCss('--c70');
    if (score >= 40) return getCss('--c40');
    return getCss('--c1');
  }
  function getCss(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }
  // The chip is coloured by class, not `style=`: index.html's CSP (default-src 'self', no
  // style-src) blocks every inline style attribute, so a style= chip renders white on white.
  function band(score, unfit) {
    if (score === null || score === undefined) return 'cna';
    if (unfit || score <= 0) return 'c0';
    if (score >= 70) return 'c70';
    if (score >= 40) return 'c40';
    return 'c1';
  }
  function fetchJson(path) {
    return fetch(path, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error(r.status + ' ' + path);
      return r.json();
    });
  }
  function haversineKm(a, b) {
    var R = 6371, dLat = (b.lat - a.lat) * Math.PI / 180, dLon = (b.lon - a.lon) * Math.PI / 180;
    var la1 = a.lat * Math.PI / 180, la2 = b.lat * Math.PI / 180;
    var h = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  function param(name) { return new URLSearchParams(location.search).get(name); }
  var setParam = I.setParam;

  /** The hour entry a beach shows for the current slider position (its best when hourIndex < 0). */
  function shown(beach) {
    var b = beach.best;
    if (state.hourIndex < 0) return { h: b.hour, score: b.score, notes: b.notes, note_codes: b.note_codes, best: true };
    var h = state.hours[state.hourIndex];
    for (var i = 0; i < beach.hours.length; i++) if (beach.hours[i].h === h) return beach.hours[i];
    return null; // dark at that hour for this beach
  }
  function isPast(h) {
    if (!state.board || state.board.day !== state.board.today) return false;
    var gen = state.board.generated_at.slice(11, 16);
    return h < gen;
  }

  // --- loading -------------------------------------------------------------------------------.
  function status(text) { el.status.textContent = text; }

  function loadAreas() {
    return fetchJson('data/areas.json').then(function (j) {
      state.areas = j.areas || [];
      if (!state.areas.length) throw new Error(t('fail.no_areas'));
      el.area.innerHTML = state.areas.map(function (a) {
        return '<option value="' + esc(a.id) + '" title="' + esc(a.name) + '" aria-label="' + esc(a.name) + '">' + esc(areaCode(a)) + '</option>';
      }).join('');
      var wanted = param('area');
      var area = state.areas.filter(function (a) { return a.id === wanted; })[0] || state.areas[0];
      el.area.value = area.id;
      return selectArea(area);
    });
  }

  // The picker shows a two-letter code; areas.json is shared with the app, so the codes live here.
  var AREA_CODES = { floripa: 'FL', rio: 'RJ', salvador: 'BA' };
  function areaCode(a) {
    return AREA_CODES[a.id] || String(a.name).normalize('NFD').replace(/[^A-Za-z]/g, '').slice(0, 2).toUpperCase();
  }

  function selectArea(area) {
    state.area = area; setParam('area', area.id); el.area.title = area.name;
    ensureMap(area);
    status(t('status.loading_named', { name: area.name }));
    return fetchJson('data/' + area.id + '/latest.json').then(function (latest) {
      state.latest = latest;
      renderDays();
      var wanted = param('day');
      var pick = latest.days.filter(function (d) { return d.day === wanted; })[0] || latest.days[latest.days.length - 1];
      return selectDay(pick);
    });
  }

  // Its own function so a language flip relabels the buttons without refetching latest.json.
  function renderDays() {
    el.days.innerHTML = state.latest.days.map(function (d, i) {
      // a third day and later are named by their date alone, so the picker fits one row on a phone
      var label = i === 0 ? tx('day.today') + ' <small>' + esc(d.day.slice(5)) + '</small>'
        : i === 1 ? tx('day.tomorrow') + ' <small>' + esc(d.day.slice(5)) + '</small>' : esc(d.day.slice(5));
      return '<button type="button"' + (d.day === state.day ? ' class="on"' : '') + ' data-day="' + esc(d.day) + '" data-file="' + esc(d.file) + '">' +
        label + '</button>';
    }).join('');
  }

  function selectDay(d) {
    state.day = d.day; setParam('day', d.day);
    Array.prototype.forEach.call(el.days.children, function (b) { b.classList.toggle('on', b.dataset.day === d.day); });
    status(t('status.loading_named', { name: d.day }));
    return fetchJson('data/' + state.area.id + '/' + d.file).then(function (board) {
      if (SCHEMAS.indexOf(board.schema) < 0) throw new Error(t('fail.schema', { got: String(board.schema), want: SCHEMAS.join(', ') }));
      state.board = board;
      state.hours = [];
      board.beaches.forEach(function (b) { b.hours.forEach(function (h) { if (state.hours.indexOf(h.h) < 0) state.hours.push(h.h); }); });
      state.hours.sort();
      el.hour.max = state.hours.length - 1;
      el.hour.value = -1; state.hourIndex = -1;
      el.hourbar.hidden = state.hours.length === 0;
      var beach = param('beach');
      if (beach && !state.selected && beachByName(beach)) state.selected = beach;
      renderWaterPoints(beachByName(state.selected));
      render();
    });
  }

  // --- map -----------------------------------------------------------------------------------.
  // The Mapbox GL licence allows it only with a Mapbox account, so with no token there is no map,
  // and the list carries the page (areas.json's `tiles` is the app's, not used here any more).
  function ensureMap(area) {
    if (!state.map && !state.mapFailed) {
      try {
        if (!window.mapboxgl || !MAPBOX.token) throw new Error('no token');
        mapboxgl.accessToken = MAPBOX.token;
        // the CSP build: the worker is a same-origin file, not a blob: (script-src 'self')
        // keyed to the bundle's version so a cached old worker never pairs with a new bundle
        mapboxgl.workerUrl = 'vendor/mapbox-gl-csp-worker.js?v=' + mapboxgl.version;
        state.map = new mapboxgl.Map({
          container: 'map', style: MAPBOX.style || DEFAULT_STYLE, projection: 'mercator',
          center: [area.lon, area.lat], zoom: 10, minZoom: 3, maxZoom: 17,
          attributionControl: true, collectResourceTiming: false, pitchWithRotate: false, dragRotate: false
        });
        state.map.touchZoomRotate.disableRotation();
        // the hour bar and footer fill in after the map is made and change #map's height
        if (window.ResizeObserver) new ResizeObserver(function () { state.map.resize(); }).observe(document.getElementById('map'));
        state.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), 'top-left');
        state.map.on('click', function (e) {
          // a click on a marker reaches the map too
          if (e.originalEvent && e.originalEvent.target && e.originalEvent.target.closest && e.originalEvent.target.closest('.mapboxgl-marker')) return;
          if (state.selected) closeCard();
        });
        state.map.on('error', function (e) {
          console.error(e && e.error ? e.error : e);
          // a refused token or a missing style never fires load: say so instead of a blank map
          var status = e && e.error && e.error.status;
          if (!state.ready && !state.mapFailed && (status === 401 || status === 403 || status === 404)) { state.mapFailed = true; mapNote('map.failed'); }
        });
        // Mapbox rebuilds its own layers after a lost GPU context, not a custom layer's GL state
        state.map.on('webglcontextrestored', function () {
          if (!state.flow || !state.map.getLayer('marola-flow')) return;
          state.map.removeLayer('marola-flow'); state.map.addLayer(state.flow, firstSymbolLayer());
        });
        state.map.on('load', function () {
          state.ready = true;
          addTrailLayer();
          state.flow = window.marolaFlow.layer({ id: 'marola-flow', still: reducedMotion(), ramps: {
            wind: [0, 1, 2, 3, 4, 5].map(function (i) { return getCss('--flow-wind-' + i); }),
            waves: [0, 1, 2, 3, 4, 5].map(function (i) { return getCss('--flow-wave-' + i); })
          } });
          // under the labels, so place names stay readable over the particles
          state.map.addLayer(state.flow, firstSymbolLayer());
          addCoastline();
          if (state.board) { renderTrails(); renderFlow(); }
        });
      } catch (e) {
        state.mapFailed = true;
        mapNote(e.message === 'no token' ? 'map.no_token' : 'map.failed');
        if (e.message !== 'no token') console.error(e);
      }
    }
    if (state.map) state.map.jumpTo({ center: [area.lon, area.lat], zoom: 10 });
  }
  function mapNote(key) {
    state.mapNoteKey = key;
    el.mapNote.textContent = t(key); el.mapNote.hidden = false;
    el.flow.hidden = true;
    el.list.hidden = false; el.toggleList.setAttribute('aria-expanded', 'true');
  }
  function reducedMotion() { return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches); }
  /** A thin coastline over the field, as Windy draws it; only Mapbox's own styles carry `composite`. */
  function addCoastline() {
    if (!state.map.getSource('composite')) return;
    state.map.addLayer({ id: 'marola-coast', type: 'line', source: 'composite', 'source-layer': 'water',
      paint: { 'line-color': 'rgba(17,24,32,0.35)', 'line-width': 0.7 } }, firstSymbolLayer());
  }
  function firstSymbolLayer() {
    var layers = (state.map.getStyle() || {}).layers || [];
    for (var i = 0; i < layers.length; i++) if (layers[i].type === 'symbol') return layers[i].id;
    return undefined;
  }

  /** A popup that shows while the pointer or keyboard focus is on el, like Leaflet's sticky tooltip did. */
  function hoverTip(node, lngLat, html, cls, offset) {
    var tip = new mapboxgl.Popup({ closeButton: false, closeOnClick: false, focusAfterOpen: false, className: cls || '',
      offset: offset || 10, maxWidth: 'none' }).setLngLat(lngLat).setHTML(html);
    var show = function () { tip.addTo(state.map); }, hide = function () { tip.remove(); };
    node.addEventListener('mouseenter', show); node.addEventListener('mouseleave', hide);
    node.addEventListener('focus', show); node.addEventListener('blur', hide);
    return tip;
  }
  function domMarker(cls, html, label, lngLat) {
    var node = document.createElement('div');
    node.className = cls; node.innerHTML = html;
    if (label) { node.setAttribute('role', 'button'); node.setAttribute('tabindex', '0'); node.setAttribute('aria-label', label); }
    return { node: node, marker: new mapboxgl.Marker({ element: node, anchor: 'center' }).setLngLat(lngLat).addTo(state.map) };
  }

  // --- the flow layer (flow.js): wind and waves as particles, from the board's own readings ----.
  /** One point per beach at the hour on show; directions are the board's (best hour) ones. */
  function flowPoints() {
    var wind = [], waves = [];
    state.board.beaches.forEach(function (b) {
      var e = hourEntry(b, shown(b));
      if (!e) return;
      wind.push({ lon: b.lon, lat: b.lat, mag: e.wind_kmh, dir: b.sea.wind_dir_deg });
      waves.push({ lon: b.lon, lat: b.lat, mag: e.wave_m, dir: b.sea.wave_dir_deg });
    });
    return { wind: wind, waves: waves };
  }
  function renderFlow() {
    Array.prototype.forEach.call(el.flow.querySelectorAll('button[data-layer]'), function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.layer === state.layer));
    });
    Array.prototype.forEach.call(el.flow.querySelectorAll('button[data-toggle]'), function (b) {
      b.setAttribute('aria-pressed', String(state[b.dataset.toggle]));
    });
    Array.prototype.forEach.call(el.keys.querySelectorAll('[data-key]'), function (k) { k.hidden = k.dataset.key !== state.layer; });
    el.map.classList.toggle('layer-water', state.layer === 'water');
    el.map.classList.toggle('no-beaches', !state.beaches);
    if (state.map && state.ready && state.map.getLayer('trails')) state.map.setLayoutProperty('trails', 'visibility', state.trails ? 'visible' : 'none');
    renderRaster();
    if (!state.flow || !state.board) return;
    state.flow.setData(flowPoints());
    state.flow.setKind(state.layer === 'wind' || state.layer === 'waves' ? state.layer : 'off');
  }

  // --- satellite layers: NASA GIBS tiles, keyless and public (the page's second third-party origin) ---.
  var LAYERS = ['wind', 'waves', 'water', 'clouds', 'sst', 'anomaly', 'elnino'];
  var GIBS = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/';
  // daysBack: VIIRS is complete the next day; MUR SST is published with about a day's lag.
  var RASTERS = {
    clouds: { layer: 'VIIRS_SNPP_CorrectedReflectance_TrueColor', matrix: 'GoogleMapsCompatible_Level9', ext: 'jpg', maxzoom: 9, daysBack: 1, opacity: 1 },
    sst: { layer: 'GHRSST_L4_MUR_Sea_Surface_Temperature', matrix: 'GoogleMapsCompatible_Level7', ext: 'png', maxzoom: 7, daysBack: 2, opacity: 0.85 },
    anomaly: { layer: 'GHRSST_L4_MUR_Sea_Surface_Temperature_Anomalies', matrix: 'GoogleMapsCompatible_Level7', ext: 'png', maxzoom: 7, daysBack: 2, opacity: 0.85 }
  };
  RASTERS.elnino = RASTERS.anomaly;
  // Niño 3.4: 5°N–5°S, 170°W–120°W, where NOAA measures El Niño.
  var NINO34 = [[-170, -5], [-120, -5], [-120, 5], [-170, 5], [-170, -5]];

  function rasterDay(r) {
    // from the day the board was made, not the forecast day: imagery for a future day does not exist
    var d = new Date((state.board ? state.board.today : new Date().toISOString().slice(0, 10)) + 'T12:00:00Z');
    d.setUTCDate(d.getUTCDate() - r.daysBack);
    return d.toISOString().slice(0, 10);
  }
  function renderRaster() {
    var r = RASTERS[state.layer];
    Array.prototype.forEach.call(el.keys.querySelectorAll('[data-when]'), function (w) {
      var k = RASTERS[w.dataset.when]; w.textContent = k ? rasterDay(k) : '';
    });
    if (!state.map || !state.ready) return;
    var id = r ? r.layer + '/' + rasterDay(r) : null;
    if (state.rasterId !== id) {
      if (state.rasterId) { state.map.removeLayer('marola-raster'); state.map.removeSource('marola-raster'); }
      state.rasterId = id;
      if (r) {
        state.map.addSource('marola-raster', { type: 'raster', tileSize: 256, maxzoom: r.maxzoom,
          attribution: '<a href="https://www.earthdata.nasa.gov/gibs">NASA GIBS</a>',
          tiles: [GIBS + r.layer + '/default/' + rasterDay(r) + '/' + r.matrix + '/{z}/{y}/{x}.' + r.ext] });
        state.map.addLayer({ id: 'marola-raster', type: 'raster', source: 'marola-raster', paint: { 'raster-opacity': r.opacity } },
          state.map.getLayer('marola-coast') ? 'marola-coast' : firstSymbolLayer());
      }
    }
    var nino = state.layer === 'elnino';
    if (nino && !state.map.getSource('nino34')) {
      state.map.addSource('nino34', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: NINO34 } } });
      state.map.addLayer({ id: 'nino34', type: 'line', source: 'nino34', paint: { 'line-color': '#ffffff', 'line-width': 1.5, 'line-dasharray': [2, 2] } });
    }
    if (state.map.getLayer('nino34')) state.map.setLayoutProperty('nino34', 'visibility', nino ? 'visible' : 'none');
    if (nino !== !!state.zoomedOut) {
      state.zoomedOut = nino;
      // the Pacific needs zoom ~1 on a phone, below the area's minZoom
      state.map.setMinZoom(nino ? 0 : 3);
      if (nino) state.map.fitBounds([[-180, -30], [-60, 25]], { padding: 20, duration: reducedMotion() ? 0 : 1200 });
      else if (state.bounds) state.map.fitBounds(state.bounds, { padding: 40, duration: reducedMotion() ? 0 : 1200, maxZoom: 13 });
    }
  }

  // --- wave markers + hover aspects (MIP-0009) ----------------------------------------------.
  // Line icons instead of emoji: Lucide's shapes (ISC, vendor/icons/LICENSE.lucide), except the
  // jellyfish, drawn here in the same 24 px, round-cap style because Lucide has none.
  var ICONS = {
    wind: '<path d="M12.8 19.6A2 2 0 1 0 14 16H2"/><path d="M17.5 8a2.5 2.5 0 1 1 2 4H2"/><path d="M9.8 4.4A2 2 0 1 1 11 8H2"/>',
    thermometer: '<path d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z"/>',
    waves: '<path d="M2 6q2.5 2 5 0t5 0 5 0 5 0"/><path d="M2 12q2.5 2 5 0t5 0 5 0 5 0"/><path d="M2 18q2.5 2 5 0t5 0 5 0 5 0"/>',
    jellyfish: '<path d="M4 12a8 8 0 0 1 16 0Z"/><path d="M8 12v3a2 2 0 0 1-1 2v2"/><path d="M12 12v9"/><path d="M16 12v3a2 2 0 0 0 1 2v2"/>',
    fish: '<path d="M6.5 12c.94-3.46 4.94-6 8.5-6 3.56 0 6.06 2.54 7 6-.94 3.47-3.44 6-7 6s-7.56-2.53-8.5-6Z"/><path d="M18 12v.5"/><path d="M16 17.93a9.77 9.77 0 0 1 0-11.86"/><path d="M7 10.67C7 8 5.58 5.97 2.73 5.5c-1 1.5-1 5 .23 6.5-1.24 1.5-1.24 5-.23 6.5C5.58 18.03 7 16 7 13.33"/>',
    footprints: '<path d="M4 16v-2.38C4 11.5 2.97 10.5 3 8c.03-2.72 1.49-6 4.5-6C9.37 2 10 3.8 10 5.5c0 3.11-2 5.66-2 8.68V16a2 2 0 1 1-4 0Z"/><path d="M20 20v-2.38c0-2.12 1.03-3.12 1-5.62-.03-2.72-1.49-6-4.5-6C14.63 6 14 7.8 14 9.5c0 3.11 2 5.66 2 8.68V20a2 2 0 1 0 4 0Z"/>',
    parking: '<circle cx="12" cy="12" r="10"/><path d="M9 17V7h4a3 3 0 0 1 0 6H9"/>',
    toilets: '<path d="M7 12h13a1 1 0 0 1 1 1 5 5 0 0 1-5 5h-.598a.5.5 0 0 0-.424.765l1.544 2.47a.5.5 0 0 1-.424.765H5.402a.5.5 0 0 1-.424-.765L7 18"/><path d="M8 18a5 5 0 0 1-5-5V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v8"/>',
    shower: '<path d="m4 4 2.5 2.5"/><path d="M13.5 6.5a4.95 4.95 0 0 0-7 7"/><path d="M15 5 5 15"/><path d="M14 17v.01"/><path d="M10 16v.01"/><path d="M13 13v.01"/><path d="M16 10v.01"/>',
    lifeguard: '<circle cx="12" cy="12" r="10"/><path d="m4.93 4.93 4.24 4.24"/><path d="m14.83 9.17 4.24-4.24"/><path d="m14.83 14.83 4.24 4.24"/><path d="m9.17 14.83-4.24 4.24"/><circle cx="12" cy="12" r="4"/>',
    book: '<path d="M12 5v16"/><path d="M20 19a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-4a5 5 0 0 0-4 2 5 5 0 0 0-4-2H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4a5 5 0 0 1 4 2 5 5 0 0 1 4-2z"/>'
  };
  function icon(name) {
    return '<svg class="ic ic-' + name + '" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' + ICONS[name] + '</svg>';
  }
  var COMPASS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'];
  function compass(deg) { return word('dir.', COMPASS[Math.round(deg / 45) % 8]); }

  // A beach is a dot in its score colour: a white ring keeps neighbours apart where beaches crowd,
  // and the picked one grows into a badge with its number. The `wave` class name is MIP-0009's.
  function waveIcon(fill, selected, score) {
    var size = selected ? 32 : 16, r = size / 2;
    var label = selected && score !== null && score !== undefined
      ? '<text x="16" y="20.5" text-anchor="middle" font-size="13" font-weight="600" fill="' + (fill === getCss('--c40') ? '#181b22' : '#fff') + '">' + esc(String(score)) + '</text>'
      : '';
    return '<svg viewBox="0 0 ' + size + ' ' + size + '" width="' + size + '" height="' + size + '" aria-hidden="true">' +
      '<circle cx="' + r + '" cy="' + r + '" r="' + (r - .5) + '" fill="#1d2733"/>' +
      '<circle cx="' + r + '" cy="' + r + '" r="' + (r - 2) + '" fill="' + esc(fill) + '" stroke="#fff" stroke-width="2"/>' + label + '</svg>';
  }

  /** The best-hour shape `shown()` returns carries no numbers; this finds the hours[] entry. */
  function hourEntry(beach, s) {
    if (!s) return null;
    for (var i = 0; i < beach.hours.length; i++) if (beach.hours[i].h === s.h) return beach.hours[i];
    return null;
  }

  // 'no data' is the one summary the board writes in words rather than the agency's verdict.
  function noWaterData(beach) { return beach.water.summary === 'no data'; }
  function waterSummary(beach) { return noWaterData(beach) ? t('water.no_data') : beach.water.summary; }
  function waterDotClass(beach) {
    if (beach.water.unfit) return 'wdot c0';
    if (noWaterData(beach)) return 'wdot cna';
    return 'wdot c70';
  }

  function wavesText(waveM, periodS) {
    return t('cell.waves', { m: fmt(waveM, ' m'), every: periodS === null || periodS === undefined ? 'no' : 'yes', s: fmt(periodS, ' s', 0) });
  }

  /** Every icon is followed by its word: the icon is decoration (aria-hidden), the word is the reading. */
  function aspectsHtml(beach, s) {
    var head = '<div class="head">' + esc(beach.name) + ' · ' + (s ? tx('tip.at', { score: s.score, h: s.h }) : tx('tip.dark')) + '</div>';
    var e = hourEntry(beach, s);
    if (!e) return head;
    var level = e.wind_level || null; // an older board has no band: number only, no word
    var kmh = fmt(e.wind_kmh, ' km/h', 0);
    var wind = icon('wind') + ' ' + (level ? esc(word('wind.', level)) + ', ' + esc(kmh) : tx('cell.wind', { v: kmh })) +
      (s.best && beach.sea.wind_dir_deg !== null ? ' <abbr class="dir">' + esc(compass(beach.sea.wind_dir_deg)) + '</abbr>' : '');
    var waves = icon('waves') + ' ' + esc(wavesText(e.wave_m, s.best ? beach.sea.period_s : null));
    var peak = beach.whales.peak && beach.whales.peak !== e.h;
    var whales = icon('fish') + ' ' + tx('cell.whales', { level: word('lvl.', e.whales), best: peak ? 'yes' : 'no', peak: beach.whales.peak || '' });
    var water = '<span class="wide ' + (beach.water.unfit ? 'unfit' : 'water') + '"><i class="' + waterDotClass(beach) + '"></i> ' + esc(waterSummary(beach)) + '</span>';
    var facilities = facilitiesHtml(beach.facilities);
    return head + '<div class="grid">' +
      '<span>' + wind + '</span>' +
      '<span>' + icon('thermometer') + ' ' + tx('cell.water', { v: fmt(e.sea_temp_c, ' °C') }) + '</span>' +
      '<span>' + waves + '</span>' +
      '<span>' + icon('jellyfish') + ' ' + tx('cell.jellyfish', { level: word('lvl.', e.jellyfish) }) + '</span>' +
      '<span>' + whales + '</span>' +
      water +
      (facilities ? '<span class="wide facilities">' + facilities + '</span>' : '') +
      '</div>';
  }

  // --- trails (MIP-0030) --------------------------------------------------------------------.
  function trailColour(difficulty) {
    if (difficulty === 'hiking') return getCss('--c70');
    if (difficulty === 'mountain_hiking') return getCss('--c40');
    return getCss('--cna');
  }
  function trailTooltipHtml(trail) {
    return icon('footprints') + ' ' + esc(trail.name) + ' · ' + fmt(trail.length_km, ' km');
  }

  // Trails are a GeoJSON line layer (one source, many features), not a layer per trail.
  function addTrailLayer() {
    state.map.addSource('trails', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
    state.map.addLayer({ id: 'trails', type: 'line', source: 'trails', layout: { 'line-cap': 'round' },
      paint: { 'line-color': ['get', 'color'], 'line-width': 3, 'line-opacity': 0.85, 'line-dasharray': [1.5, 1.5] } });
    var tip = new mapboxgl.Popup({ closeButton: false, closeOnClick: false, offset: 8, maxWidth: 'none' });
    state.map.on('mousemove', 'trails', function (e) {
      var f = e.features && e.features[0]; if (!f) return;
      state.map.getCanvas().style.cursor = 'default';
      tip.setLngLat(e.lngLat).setHTML(f.properties.tip).addTo(state.map);
    });
    state.map.on('mouseleave', 'trails', function () { tip.remove(); });
  }
  function renderTrails() {
    if (!state.ready) return;
    var features = (state.board.trails || []).filter(function (trail) { return (trail.geometry || []).length >= 2; }).map(function (trail) {
      return { type: 'Feature', properties: { color: trailColour(trail.difficulty), tip: trailTooltipHtml(trail) },
        geometry: { type: 'LineString', coordinates: trail.geometry.map(function (p) { return [p[1], p[0]]; }) } };
    });
    state.map.getSource('trails').setData({ type: 'FeatureCollection', features: features });
  }

  function facilitiesHtml(f) {
    if (!f) return '';
    var parts = ['parking', 'toilets', 'shower', 'lifeguard']
      .filter(function (k) { return f[k] !== undefined && f[k] !== null; })
      .map(function (k) { return icon(k) + ' ' + tx('fac.' + k, { n: f[k] }); });
    return parts.join(' · ');
  }

  function render() {
    var board = state.board;
    if (state.map) renderMarkers(board);
    renderHourLabel();
    renderList();
    renderFooter();
    renderFlow();
    if (state.selected) renderCard();
  }

  function renderMarkers(board) {
    Object.keys(state.markers).forEach(function (k) { state.markers[k].marker.remove(); state.markers[k].tip.remove(); });
    state.markers = {};
    renderTrails();
    var w = Infinity, e = -Infinity, s0 = Infinity, n = -Infinity;
    board.beaches.forEach(function (beach) {
      var s = shown(beach);
      var selected = state.selected === beach.name;
      var past = !!(s && isPast(s.h));
      // No `title`: the browser would draw a native tooltip on top of the popup.
      var m = domMarker('wave' + (selected ? ' selected' : '') + (past ? ' past' : ''),
        waveIcon(colour(s ? s.score : null, beach.water.unfit), selected, s ? s.score : null), beach.name, [beach.lon, beach.lat]);
      m.tip = hoverTip(m.node, [beach.lon, beach.lat], aspectsHtml(beach, s), 'aspects', selected ? 18 : 10);
      m.node.addEventListener('click', function (ev) { if (ev && ev.stopPropagation) ev.stopPropagation(); select(beach.name, false); });
      m.node.addEventListener('keydown', function (ev) {
        if (ev.key === 'Enter' || ev.key === ' ') { if (ev.preventDefault) ev.preventDefault(); select(beach.name, false); }
      });
      state.markers[beach.name] = m;
      w = Math.min(w, beach.lon); e = Math.max(e, beach.lon); s0 = Math.min(s0, beach.lat); n = Math.max(n, beach.lat);
    });
    if (board.beaches.length) state.bounds = [[w, s0], [e, n]];
    if (board.beaches.length && !state.fitted && !state.zoomedOut) {
      state.map.fitBounds(state.bounds, { padding: 40, duration: 0, maxZoom: 13 }); state.fitted = true;
    }
  }

  function renderHourLabel() {
    if (state.hourIndex < 0) { el.hourLabel.textContent = t('hour.best'); return; }
    var h = state.hours[state.hourIndex];
    el.hourLabel.textContent = t('hour.at', { h: h, past: isPast(h) ? 'yes' : 'no' });
  }

  // --- list ----------------------------------------------------------------------------------.
  function ranked() {
    var list = state.board.beaches.slice();
    if (state.here) {
      list.forEach(function (b) { b._km = haversineKm(state.here, b); });
      list.sort(function (a, b) { return a._km - b._km; });
    } else {
      list.sort(function (a, b) { var sa = shown(a), sb = shown(b); return (sb ? sb.score : -1) - (sa ? sa.score : -1); });
    }
    return list;
  }

  function renderList() {
    var items = ranked().map(function (b) {
      var s = shown(b);
      var score = s ? s.score : '–';
      var water = b.water.unfit ? '<span class="water unfit">' + esc(waterSummary(b)) + '</span>'
        : (b.water.points.length ? '<span class="water">' + esc(waterSummary(b)) + '</span>' : '');
      var dist = state.here ? ' <span class="dist">' + num(b._km, 1) + ' km</span>' : '';
      return '<li data-name="' + esc(b.name) + '"><span class="score ' + band(s ? s.score : null, b.water.unfit) + '">' + score + '</span>' +
        esc(b.name) + ' <span class="dist">' + (s ? esc(s.h) : tx('list.dark')) + '</span>' + dist + water + '</li>';
    });
    el.list.innerHTML = '<ol>' + items.join('') + '</ol>';
  }

  // --- card ----------------------------------------------------------------------------------.
  function select(name, pan) {
    state.selected = name; setParam('beach', name);
    var b = beachByName(name);
    if (b && pan !== false && state.map) state.map.panTo([b.lon, b.lat]);
    renderWaterPoints(b);
    render();
  }
  function closeCard() {
    state.selected = null; el.card.hidden = true;
    var u = new URL(location.href); u.searchParams.delete('beach'); history.replaceState(null, '', u);
    renderWaterPoints(null);
    render();
  }
  function beachByName(name) {
    return state.board.beaches.filter(function (b) { return b.name === name; })[0] || null;
  }

  function condLabel(c) { return c === 'proper' ? 'PRÓPRIA' : c === 'improper' ? 'IMPRÓPRIA' : t('water.unclassified'); }

  /** The water layer shows every beach's sampling points; the others only the selected beach's. */
  function renderWaterPoints(beach) {
    state.waterPointMarkers.forEach(function (m) { m.marker.remove(); m.tip.remove(); });
    state.waterPointMarkers = [];
    if (!state.map) return;
    var beaches = state.layer === 'water' && state.board ? state.board.beaches : beach ? [beach] : [];
    beaches.forEach(function (b) { if (b.water && b.water.points) b.water.points.forEach(addWaterPoint); });
  }
  function addWaterPoint(p) {
    var band = p.condition === 'improper' ? 'c0' : p.condition === 'proper' ? 'c70' : 'cna';
    var text = esc(p.point) + ' (' + esc(p.location) + '): ' + esc(condLabel(p.condition)) + ', ' + esc(p.sampled_on);
    var m = domMarker('wpoint ' + band, '', p.point, [p.lon, p.lat]);
    m.tip = hoverTip(m.node, [p.lon, p.lat], '<span class="water">' + text + '</span>', '', 8);
    state.waterPointMarkers.push(m);
  }

  // task 3's note codes carry raw numbers; round them as the English notes did.
  var NOTE_ARGS = {
    wave_m: function (v) { return num(v, 1); },
    sea_temp_c: function (v) { return num(v, 1); },
    wind_kmh: function (v) { return num(v, 0); },
    rain_pct: function (v) { return num(v, 0); },
    sampled_on: shortDate,
    avoid: function (v) { return v.join('; '); }
  };
  /** note.<code> in the current language; a code this page has no key for keeps the board's English. */
  function noteText(code, english) {
    var a = code.args || {}, args = {};
    Object.keys(a).forEach(function (k) { args[k] = NOTE_ARGS[k] ? NOTE_ARGS[k](a[k]) : a[k]; });
    if (args.enterococci_per_100ml === undefined || args.enterococci_per_100ml === null) args.enterococci_per_100ml = 'na';
    var key = 'note.' + code.code, out = t(key, args);
    return out === key ? (english || code.code) : out;
  }
  function notesOf(s) {
    if (!s.note_codes || !s.note_codes.length) return s.notes;
    return s.note_codes.map(function (c, i) { return noteText(c, s.notes[i]); });
  }

  function renderCard() {
    var b = beachByName(state.selected);
    if (!b) { el.card.hidden = true; return; }
    var s = shown(b);
    var head = s
      ? '<p class="headline"><span class="score ' + band(s.score, b.water.unfit) + '">' + s.score + '/100</span> ' +
        (s.best ? t('card.best_at', { h: '<b>' + esc(s.h) + '</b>' })
          : t('card.at_best', { h: '<b>' + esc(s.h) + '</b>', best: esc(b.best.hour), score: b.best.score })) +
        (isPast(s.h) ? ' <span class="past">' + tx('card.past') + '</span>' : '') + '</p>'
      : '<p class="headline past">' + tx('tip.dark') + '</p>';
    var notes = s ? notesOf(s) : [];
    var why = notes.length ? '<ul>' + notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('') + '</ul>' : tx('card.good');
    var points = b.water.points.map(function (p) {
      var cls = p.condition === 'improper' ? 'water improper' : p.condition === 'proper' ? 'water proper' : 'water';
      var count = p.enterococci_per_100ml === null ? '' : ', ' + tx('card.enterococci', { n: p.enterococci_per_100ml });
      return '<li><span class="' + cls + '">' + esc(p.point) + ' (' + esc(p.location) + '): ' + esc(condLabel(p.condition)) + '</span>, ' + esc(p.sampled_on) + count + '</li>';
    });
    var water = '<span class="' + (b.water.unfit ? 'unfit' : 'water') + '">' + esc(waterSummary(b)) + '</span>' +
      (points.length ? '<ul>' + points.join('') + '</ul>' : '') +
      (b.water.source ? '<small>' + t('card.source', { source: '<span class="src">' + esc(b.water.source) + '</span>' }) + '</small>' : '');
    var signed = new Intl.NumberFormat(I.locale(), { signDisplay: 'exceptZero', minimumFractionDigits: 1, maximumFractionDigits: 1 });
    var tides = b.tides.length ? b.tides.map(function (td) {
      return tx(td.high ? 'tide.high' : 'tide.low', { time: td.time, m: signed.format(td.m) });
    }).join(', ') + ' <small>' + tx('tide.hourly') + '</small>' : tx('tide.none');
    var sea = b.sea;
    var seaText = [fmt(sea.temp_c, '°C'), wavesText(sea.wave_m, sea.period_s)]
      .concat(sea.swell_m !== null ? [t('card.swell', { v: fmt(sea.swell_m, ' m') })] : [])
      .concat(sea.current_kmh !== null ? [t('card.current', { v: fmt(sea.current_kmh, ' km/h') })] : []).join(', ');
    var air = [fmt(sea.air_temp_c, '°C', 0), t('cell.wind', { v: fmt(sea.wind_kmh, ' km/h', 0) })]
      .concat(sea.uv !== null ? [t('card.uv', { v: fmt(sea.uv, '', 0) })] : [])
      .concat(sea.rain_pct !== null ? [t('card.rain', { pct: num(sea.rain_pct, 0) })] : []).join(', ');
    var whales = t('card.whales_now', { level: word('lvl.', b.whales.now), best: b.whales.peak ? 'yes' : 'no',
      peak: b.whales.peak || '', season: b.whales.season ? 'yes' : 'no' });
    el.card.innerHTML =
      '<button class="close" type="button" aria-label="' + tx('card.close') + '">×</button>' +
      '<h2>' + esc(b.name) + '</h2>' +
      // Touch has no hover: the tooltip's aspect row, first (MIP-0009 §3).
      '<div class="aspects">' + aspectsHtml(b, s) + '</div>' + head +
      '<dl>' +
      '<dt>' + tx('card.why') + '</dt><dd>' + why + '</dd>' +
      '<dt>' + tx('card.water') + '</dt><dd>' + water + '</dd>' +
      '<dt>' + tx('card.sea') + '</dt><dd>' + esc(seaText) + ' <small>' + tx('card.at', { h: b.best.hour }) + '</small></dd>' +
      '<dt>' + tx('card.tide') + '</dt><dd>' + tides + '</dd>' +
      '<dt>' + tx('card.air') + '</dt><dd>' + esc(air) + '</dd>' +
      '<dt>' + tx('card.jellyfish') + '</dt><dd>' + esc(word('lvl.', b.jellyfish)) + '</dd>' +
      '<dt>' + tx('card.whales') + '</dt><dd>' + esc(whales) + '</dd>' +
      // Coordinates keep the dot in every language: a decimal comma would collide with the separator.
      '<dt>' + tx('card.where') + '</dt><dd><a href="https://www.openstreetmap.org/?mlat=' + b.lat + '&mlon=' + b.lon + '#map=15/' + b.lat + '/' + b.lon + '" target="_blank" rel="noopener">' + b.lat.toFixed(4) + ', ' + b.lon.toFixed(4) + '</a></dd>' +
      '</dl>';
    el.card.hidden = false;
    el.card.querySelector('.close').addEventListener('click', closeCard);
  }

  // --- footer --------------------------------------------------------------------------------.
  function renderFooter() {
    var b = state.board;
    var srcs = [b.sources.beaches, b.sources.forecast, b.sources.water].filter(Boolean).map(function (s) {
      var href = SOURCE_LINKS[s.split(' ')[0]] || SOURCE_LINKS[s];
      var label = href ? '<a href="' + href + '" target="_blank" rel="noopener">' + esc(s) + '</a>' : esc(s);
      return '<span class="src">' + label + '</span>';
    }).join(' · ');
    var lore = b.lore ? '<p class="lore">' + (b.lore.kind === 'creature' ? icon('fish') + ' ' + tx('lore.creature') : icon('book') + ' ' + tx('lore.fact')) + ' ' + esc(b.lore.text) +
      ' <a href="' + esc(b.lore.source) + '" target="_blank" rel="noopener">[' + tx('lore.source') + ']</a></p>' : '';
    el.footer.innerHTML =
      '<p id="status">' + t('footer.generated', { when: esc(b.generated_at.replace('T', ' ').slice(0, 16)), area: esc(state.area.name),
        day: esc(b.day), n: b.beaches.length, sources: srcs }) + '</p>' + lore +
      '<p>' + tx('footer.blurb') + ' <a href="' + REPO + '" target="_blank" rel="noopener">' + tx('footer.github') + '</a>.</p>';
    el.status = document.getElementById('status');
  }

  // --- ambient wave sound: a recorded loop (vendor/sounds/LICENSE.waves), fetched on first use ----.
  var sound = { ctx: null, gain: null, on: false };
  var SOUND_URL = 'vendor/sounds/waves.mp3';
  var SOUND_LEVEL = 0.6;
  var SILENT = 0.0001;
  function startWaveSound(ctx) {
    var gainNode = ctx.createGain();
    gainNode.gain.value = SILENT;
    gainNode.connect(ctx.destination);
    fetch(SOUND_URL).then(function (r) {
      if (!r.ok) throw new Error(r.status + ' ' + SOUND_URL);
      return r.arrayBuffer();
    }).then(function (bytes) {
      // the callback form: Safari before 14.1 has no promise-returning decodeAudioData
      return new Promise(function (resolve, reject) { ctx.decodeAudioData(bytes, resolve, reject); });
    }).then(function (audio) {
      var src = ctx.createBufferSource();
      src.buffer = audio; src.loop = true;
      // skip the MP3 encoder's padding at both ends, which would click at every loop
      src.loopStart = 0.05; src.loopEnd = audio.duration - 0.05;
      src.connect(gainNode);
      src.start(0, 0.05);
    }).catch(function (e) {
      console.error(e);
      // the next click tries again from scratch
      sound.on = false; el.sound.setAttribute('aria-pressed', 'false');
      if (ctx.close) ctx.close();
      if (sound.ctx === ctx) sound.ctx = null;
    });
    return { gain: gainNode };
  }

  // --- events --------------------------------------------------------------------------------.
  el.area.addEventListener('change', function () {
    var area = state.areas.filter(function (a) { return a.id === el.area.value; })[0];
    state.fitted = false; state.selected = null; el.card.hidden = true;
    selectArea(area).catch(fail);
  });
  el.days.addEventListener('click', function (e) {
    var btn = e.target.closest('button'); if (!btn) return;
    selectDay({ day: btn.dataset.day, file: btn.dataset.file }).catch(fail);
  });
  el.hour.addEventListener('input', function () { state.hourIndex = parseInt(el.hour.value, 10); render(); });
  el.flow.addEventListener('click', function (e) {
    var btn = e.target.closest('button'); if (!btn) return;
    if (btn.disabled) return;
    var t = btn.dataset.toggle;
    if (t === 'beaches' || t === 'trails') { state[t] = !state[t]; setParam(t, state[t] ? '1' : '0'); }
    // a pressed layer button turns its layer off again
    else if (btn.dataset.layer) { state.layer = btn.dataset.layer === state.layer ? 'off' : btn.dataset.layer; setParam('layer', state.layer); }
    else return;
    renderFlow();
    if (state.board) renderWaterPoints(beachByName(state.selected));
  });
  el.toggleList.addEventListener('click', function () {
    el.list.hidden = !el.list.hidden;
    el.toggleList.setAttribute('aria-expanded', String(!el.list.hidden));
  });
  el.list.addEventListener('click', function (e) {
    var li = e.target.closest('li'); if (li) select(li.dataset.name, true);
  });
  el.near.addEventListener('click', function () {
    if (state.here) { state.here = null; el.near.setAttribute('aria-pressed', 'false'); render(); return; }
    if (!navigator.geolocation) { alert(t('near.unsupported')); return; }
    navigator.geolocation.getCurrentPosition(function (pos) {
      state.here = { lat: pos.coords.latitude, lon: pos.coords.longitude };
      el.near.setAttribute('aria-pressed', 'true');
      el.list.hidden = false; el.toggleList.setAttribute('aria-expanded', 'true');
      if (state.map) {
        if (state.hereMarker) { state.hereMarker.marker.remove(); state.hereMarker.tip.remove(); }
        state.hereMarker = domMarker('here', '', null, [state.here.lon, state.here.lat]);
        state.hereMarker.tip = hoverTip(state.hereMarker.node, [state.here.lon, state.here.lat], tx('near.you'), '', 8);
      }
      render();
    }, function () { alert(t('near.denied')); });
  });
  el.sound.addEventListener('click', function () {
    try {
      if (!sound.ctx) {
        var Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) return;
        sound.ctx = new Ctx();
        sound.gain = startWaveSound(sound.ctx).gain;
      }
      if (sound.ctx.state === 'suspended') sound.ctx.resume();
      sound.on = !sound.on;
      el.sound.setAttribute('aria-pressed', String(sound.on));
      var now = sound.ctx.currentTime;
      sound.gain.gain.cancelScheduledValues(now);
      sound.gain.gain.setTargetAtTime(sound.on ? SOUND_LEVEL : SILENT, now, 0.5);
    } catch (e) { console.error(e); }
  });

  function fail(err) {
    var msg = (err && err.message) || String(err);
    // fetchJson's error is "<status> <path>"; only a missing board JSON means "not built yet".
    status(t('fail.load', { error: msg, hint: /^404 data\/.*\.json$/.test(msg) ? 'yes' : 'no' }));
    console.error(err);
  }

  // ui.js has already rewritten the static text; this redraws what app.js built, from state, no fetch.
  I.onLang(function () {
    if (state.latest) renderDays();
    if (!state.board) return;
    render();
    renderWaterPoints(beachByName(state.selected));
    if (state.hereMarker) state.hereMarker.tip.setHTML(tx('near.you'));
    if (state.mapNoteKey) el.mapNote.textContent = t(state.mapNoteKey);
  });

  // the rail's markup says which layers are built: a disabled button ("em breve") is never shown,
  // even from a ?layer= link
  function enabled(attr, value) {
    return Array.prototype.some.call(el.flow.querySelectorAll('button[data-' + attr + ']'), function (b) {
      return b.dataset[attr] === value && !b.disabled;
    });
  }
  if (LAYERS.indexOf(param('layer')) >= 0 && enabled('layer', param('layer'))) state.layer = param('layer');
  if (param('beaches') === '0') state.beaches = false;
  if (param('trails') === '0' || !enabled('toggle', 'trails')) state.trails = false;

  loadAreas().catch(fail);
})();
