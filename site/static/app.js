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
    list: $('list'), card: $('card'), footer: $('footer'), status: $('status')
  };

  var state = {
    areas: [], area: null, latest: null, board: null,
    hours: [],          // union of "HH:00" across beaches, sorted — the slider's stops
    hourIndex: -1,      // -1 = each beach at its own best hour
    selected: null,     // beach name
    here: null,         // {lat, lon} after "near me"
    markers: {}, trailLayers: [], tiles: null, map: null,
    waterPointMarkers: []
  };

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
        return '<option value="' + esc(a.id) + '">' + esc(a.name) + '</option>';
      }).join('');
      var wanted = param('area');
      var area = state.areas.filter(function (a) { return a.id === wanted; })[0] || state.areas[0];
      el.area.value = area.id;
      return selectArea(area);
    });
  }

  function selectArea(area) {
    state.area = area; setParam('area', area.id);
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
      var label = i === 0 ? tx('day.today') : i === 1 ? tx('day.tomorrow') : esc(d.day);
      return '<button type="button"' + (d.day === state.day ? ' class="on"' : '') + ' data-day="' + esc(d.day) + '" data-file="' + esc(d.file) + '">' +
        label + ' <small>' + esc(d.day.slice(5)) + '</small></button>';
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
  function ensureMap(area) {
    if (!state.map) {
      state.map = L.map('map', { zoomControl: true, attributionControl: true });
      state.map.on('click', function () { closeCard(); });
    }
    if (state.tiles) state.map.removeLayer(state.tiles);
    state.tiles = L.tileLayer(area.tiles, { maxZoom: 18, attribution: esc(area.tiles_attribution || '') }).addTo(state.map);
    state.map.setView([area.lat, area.lon], 11);
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
  function waveIcon(fill, selected, past, score) {
    var size = selected ? 32 : 16, r = size / 2;
    var label = selected && score !== null && score !== undefined
      ? '<text x="16" y="20.5" text-anchor="middle" font-size="13" font-weight="600" fill="' + (fill === getCss('--c40') ? '#181b22' : '#fff') + '">' + esc(String(score)) + '</text>'
      : '';
    return L.divIcon({
      className: 'wave' + (selected ? ' selected' : '') + (past ? ' past' : ''),
      iconSize: [size, size], iconAnchor: [r, r], tooltipAnchor: [0, -r],
      html: '<svg viewBox="0 0 ' + size + ' ' + size + '" width="' + size + '" height="' + size + '" aria-hidden="true">' +
        '<circle cx="' + r + '" cy="' + r + '" r="' + (r - .5) + '" fill="#0b3d8c"/>' +
        '<circle cx="' + r + '" cy="' + r + '" r="' + (r - 2) + '" fill="' + esc(fill) + '" stroke="#fff" stroke-width="2"/>' + label + '</svg>'
    });
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

  function renderTrails() {
    state.trailLayers.forEach(function (l) { state.map.removeLayer(l); });
    state.trailLayers = [];
    (state.board.trails || []).forEach(function (trail) {
      var latlngs = (trail.geometry || []).map(function (p) { return [p[0], p[1]]; });
      if (latlngs.length < 2) return;
      var line = L.polyline(latlngs, {
        color: trailColour(trail.difficulty), weight: 3, opacity: 0.8, dashArray: '4,4'
      }).addTo(state.map);
      line.bindTooltip(trailTooltipHtml(trail), { sticky: true, direction: 'top' });
      state.trailLayers.push(line);
    });
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
    Object.keys(state.markers).forEach(function (k) { state.map.removeLayer(state.markers[k]); });
    state.markers = {};
    renderTrails();
    var bounds = [];
    board.beaches.forEach(function (beach) {
      var s = shown(beach);
      var c = colour(s ? s.score : null, beach.water.unfit);
      var selected = state.selected === beach.name;
      var m = L.marker([beach.lat, beach.lon], {
        icon: waveIcon(c, selected, !!(s && isPast(s.h)), s ? s.score : null), zIndexOffset: selected ? 1000 : 0, keyboard: true
      }).addTo(state.map);
      // No `title`: the browser would draw a native tooltip on top of Leaflet's.
      if (m.getElement) { var mel = m.getElement(); if (mel) mel.setAttribute('aria-label', beach.name); }
      m.bindTooltip(aspectsHtml(beach, s), { sticky: true, direction: 'top', className: 'aspects', opacity: 0.97 });
      m.on('click', function (e) { L.DomEvent.stopPropagation(e); select(beach.name, false); });
      state.markers[beach.name] = m;
      bounds.push([beach.lat, beach.lon]);
    });
    if (bounds.length && !state.fitted) { state.map.fitBounds(bounds, { padding: [30, 30] }); state.fitted = true; }
    renderHourLabel();
    renderList();
    renderFooter();
    if (state.selected) renderCard();
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
    if (b && pan !== false) state.map.panTo([b.lat, b.lon]);
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

  function renderWaterPoints(beach) {
    state.waterPointMarkers.forEach(function (m) { state.map.removeLayer(m); });
    state.waterPointMarkers = [];
    if (!beach || !beach.water || !beach.water.points) return;
    beach.water.points.forEach(function (p) {
      var color = p.condition === 'improper' ? getCss('--c0') : p.condition === 'proper' ? getCss('--c70') : getCss('--cna');
      var m = L.circleMarker([p.lat, p.lon], { radius: 6, color: '#fff', weight: 2, fillColor: color, fillOpacity: 1 })
        .addTo(state.map)
        .bindTooltip(esc(p.point) + ' (' + esc(p.location) + '): ' + esc(condLabel(p.condition)) + ', ' + esc(p.sampled_on), { direction: 'top', offset: [0, -6] });
      state.waterPointMarkers.push(m);
    });
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

  // --- ambient wave sound (Web Audio, synthesized — nothing to fetch) ------------------------.
  var sound = { ctx: null, gain: null, lfoDepth: null, on: false };
  var SWELL_DEPTH = 0.05;   // how far the LFO swings the output gain when the sound is on
  var SOUND_LEVEL = 0.06;   // the output gain's own level when on
  var SILENT = 0.0001;
  // Low-passed brown noise reads as surf wash; a ~0.15 Hz LFO on the gain adds the swell.
  function startWaveSound(ctx) {
    var seconds = 2, bufferSize = seconds * ctx.sampleRate;
    var buffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    var data = buffer.getChannelData(0);
    var last = 0;
    for (var i = 0; i < bufferSize; i++) {
      var white = Math.random() * 2 - 1;
      last = (last + 0.02 * white) / 1.02;
      data[i] = last * 3.5;
    }
    var noise = ctx.createBufferSource();
    noise.buffer = buffer; noise.loop = true;
    var filter = ctx.createBiquadFilter();
    filter.type = 'lowpass'; filter.frequency.value = 700;
    var gainNode = ctx.createGain();
    gainNode.gain.value = SILENT;
    var lfo = ctx.createOscillator();
    lfo.frequency.value = 0.15;
    var lfoGain = ctx.createGain();
    lfoGain.gain.value = SWELL_DEPTH;
    lfo.connect(lfoGain);
    lfoGain.connect(gainNode.gain);
    noise.connect(filter);
    filter.connect(gainNode);
    gainNode.connect(ctx.destination);
    noise.start(); lfo.start();
    // Both must be silenced to stop the sound: a signal connected to an AudioParam is *added* to
    // its value, so zeroing gainNode.gain alone leaves the LFO swinging it by ±SWELL_DEPTH.
    return { gain: gainNode, lfoDepth: lfoGain };
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
      state.hereMarker = L.circleMarker([state.here.lat, state.here.lon], { radius: 6, color: '#4098ff', fillColor: '#4098ff', fillOpacity: 1 })
        .addTo(state.map).bindTooltip(tx('near.you'));
      render();
    }, function () { alert(t('near.denied')); });
  });
  el.sound.addEventListener('click', function () {
    try {
      if (!sound.ctx) {
        var Ctx = window.AudioContext || window.webkitAudioContext;
        if (!Ctx) return;
        sound.ctx = new Ctx();
        var synth = startWaveSound(sound.ctx);
        sound.gain = synth.gain;
        sound.lfoDepth = synth.lfoDepth;
      }
      if (sound.ctx.state === 'suspended') sound.ctx.resume();
      sound.on = !sound.on;
      el.sound.setAttribute('aria-pressed', String(sound.on));
      var now = sound.ctx.currentTime;
      sound.gain.gain.cancelScheduledValues(now);
      sound.gain.gain.setTargetAtTime(sound.on ? SOUND_LEVEL : SILENT, now, 0.5);
      sound.lfoDepth.gain.cancelScheduledValues(now);
      sound.lfoDepth.gain.setTargetAtTime(sound.on ? SWELL_DEPTH : 0, now, 0.5);
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
    if (state.hereMarker) state.hereMarker.bindTooltip(tx('near.you'));
  });

  loadAreas().catch(fail);
})();
