// Why this file exists: Elm has no binding for MapLibre, WebGL, geolocation, localStorage, history,
// the document's lang or alert, so it reaches them through ports (ADR 0007). This file starts the page
// and carries out each of those effects Main.elm sends (js/maplibre_ffi.mjs, js/flow_layer_ffi.mjs).
// Requests and focus are Elm's own (elm/http, Browser.Dom). Answers go back as plain JSON.
import { Elm } from "./src/Main.elm";
import * as ffi from "./js/maplibre_ffi.mjs";

const flags = { ...JSON.parse(ffi.readEnv()), stored: ffi.readLanguage() };
const app = Elm.Main.init({ node: document.getElementById("app"), flags });
const send = (message) => app.ports.fromJs.send(message);

const run = {
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
};

app.ports.toJs.subscribe((c) => run[c.kind](c));
