// Why this file exists: Elm reaches the browser only through ports. This file starts the page and
// carries out each effect Main.elm sends: fetch, MapLibre and the flow layer (js/maplibre_ffi.mjs,
// js/flow_layer_ffi.mjs), history, storage, audio and focus. Answers go back as plain JSON.
import { Elm } from "./src/Main.elm";
import * as ffi from "./js/maplibre_ffi.mjs";

const flags = { ...JSON.parse(ffi.readEnv()), stored: ffi.readLanguage() };
const app = Elm.Main.init({ node: document.getElementById("app"), flags });
const send = (message) => app.ports.fromJs.send(message);

// status 0 is a body, -1 a network failure, else the HTTP status.
const get = (url) =>
  fetch(url)
    .then((r) => (r.ok ? r.text().then((b) => [b, 0]) : [null, r.status]))
    .catch(() => [null, -1]);

const run = {
  fetch: (c) => get(c.url).then(([body, status]) => send({ kind: "fetched", req: c.req, status, body })),
  replaceUrl: (c) => ffi.replaceUrl(c.path, c.query),
  setDocument: (c) => ffi.setDocument(c.language, c.title),
  storeLanguage: (c) => ffi.storeLanguage(c.tag),
  initMap: (c) => ffi.initMap(c.json, (event, arg) => send({ kind: "map", event, arg: String(arg) })),
  syncMap: (c) => ffi.syncMap(c.json),
  setTrails: (c) => ffi.setTrails(c.json),
  setFlow: (c) => ffi.setFlow(c.json),
  camera: (c) => ffi.camera(c.json),
  locate: () => ffi.locate((lat, lon) => send({ kind: "located", lat, lon }), (why) => send({ kind: "locateFailed", why: String(why) })),
  alert: (c) => ffi.alertText(c.text),
  sound: (c) => ffi.playSound(c.on, c.url, () => send({ kind: "soundFailed" })),
  focus: (c) => ffi.focusId(c.id),
};

app.ports.toJs.subscribe((c) => run[c.kind](c));
