// site_check — run site/static/app.js in a stub DOM against a built site/dist and print what it
// rendered: markers, list rows, footer, the "Last live run" panel (MIP-0008) when smoke/ exists.
const fs = require('fs'), path = require('path');
const dist = process.argv[2] || 'site/dist';
if (!fs.existsSync(path.join(dist, 'data', 'areas.json'))) { console.error('no ' + dist + '/data/areas.json — build the site first'); process.exit(1); }
function El(id) {
  return { id, innerHTML: '', textContent: '', hidden: false, value: '', max: 0, children: [], dataset: {}, _cls: new Set(),
    classList: { toggle(c, on) { on ? this._s.add(c) : this._s.delete(c); }, _s: new Set() },
    addEventListener() {}, setAttribute() {}, getAttribute() { return null; },
    querySelector() { return { addEventListener() {} }; }, querySelectorAll() { return []; } };
}
const els = {};
global.document = {
  createElement() { return El('div'); },
  getElementById(id) { return els[id] || (els[id] = El(id)); },
  querySelectorAll() { return []; }, documentElement: {}, addEventListener() {}
};
global.getComputedStyle = () => ({ getPropertyValue: () => '#000' });
global.location = { search: '', href: 'http://localhost/' };
global.history = { replaceState() {} };
global.navigator = {};
global.URLSearchParams = URLSearchParams; global.URL = URL;
const calls = { markers: [] };
// a Mapbox GL just big enough: DOM markers are recorded by their element's class
class Popup { setLngLat() { return this; } setHTML() { return this; } addTo() { return this; } remove() { return this; } }
class Marker {
  constructor(o) { calls.markers.push(o.element); }
  setLngLat() { return this; } addTo() { return this; } remove() { return this; }
}
class MapStub {
  constructor() { this.touchZoomRotate = { disableRotation() {} }; }
  on() { return this; } addControl() {} jumpTo() {} fitBounds() {} panTo() {} resize() {}
  getStyle() { return { layers: [] }; } addSource() {} getSource() { return { setData() {} }; } addLayer() {}
}
global.mapboxgl = { Map: MapStub, Marker, Popup, NavigationControl: function () {} };
global.MAROLA_MAPBOX = { token: 'pk.local-check' };
global.fetch = async (p) => {
  const f = path.join(dist, p);
  if (!fs.existsSync(f)) return { ok: false, status: 404 };
  return { ok: true, status: 200, json: async () => JSON.parse(fs.readFileSync(f, 'utf8')) };
};
global.window = global;
for (const f of ['i18n.js', 'ui.js', 'flow.js', 'app.js']) require(path.join(process.cwd(), 'site/static', f));
process.on('unhandledRejection', (e) => { console.error('app.js rejected:', e); process.exit(1); });
setTimeout(() => {
  const smoke = els.smoke || {}, footer = els.footer || {}, list = els.list || {};
  const beaches = calls.markers.filter(m => /\bwave\b/.test(m.className)).length;
  console.log('beach markers:', beaches);
  console.log('list rows:', (list.innerHTML || '').split('<li').length - 1);
  console.log('footer:', (footer.innerHTML || '').replace(/<[^>]+>/g, '').slice(0, 140));
  if (smoke.innerHTML) console.log('smoke panel:', smoke.hidden ? 'hidden' : smoke.innerHTML.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').slice(0, 220));
  if (!beaches) { console.log('SITE CHECK FAILED: no beach markers drawn'); process.exit(1); }
  console.log('SITE CHECK OK');
}, 400);
