# Libraries

Plain JavaScript, no framework and no build step ([`AGENTS.md`](../AGENTS.md)'s Code style
section): every file under `site/static/` ships to the browser exactly as it sits in the repo, and
`just site-build` only copies `site/static/.` into `site/dist/` — it does not bundle or transpile
anything. Everything below lives under `site/static/vendor/`, vendored rather than pulled from a
CDN, so the CSP in [design.md](1-design.md#csp-and-the-no-third-party-rule) can keep
`default-src 'self'`.

| Library | Version | Why vendored | Licence |
|---|---|---|---|
| Mapbox GL JS | 3.32.0 (the CSP build, `vendor/mapbox-gl-csp.js` + `vendor/mapbox-gl-csp-worker.js`) | The base map; its custom-layer API backs `flow.js`'s WebGL wind/wave particles. Needs a Mapbox account and `pk.` token at runtime regardless of vendoring ([tile policy](4-reference.md#tile-policy)) | Mapbox TOS (`vendor/LICENSE.mapbox-gl`): usable only with a Mapbox account in good standing, not a permissive open-source licence |
| Inter (variable weight) | self-hosted woff2 (`vendor/fonts/inter-latin-wght-normal.woff2`) | A public-information, accessibility-first page; never pulled from a font CDN (no third-party font origin) | SIL OFL 1.1 (`vendor/fonts/LICENSE.inter`) |
| Lucide icons | inlined per-icon through `icon(name)` in `app.js` | Line icons, 16 px, matching [`DESIGN.md`](../DESIGN.md)'s one-icon-style rule | ISC, plus MIT for the icons descended from Feather (`vendor/icons/LICENSE.lucide` lists which) |
| "Oceanwavescrushing" (waves.mp3) | re-encoded to 48 kbit/s mono | The `#sound` toggle's ambient loop | CC BY 3.0, via Luftrum → Blanket → marola's re-encode (`vendor/sounds/LICENSE.waves`) |

## What Mapbox replaced

The original map (MIP-0005) was Leaflet over OpenStreetMap's tile servers. [PR
#44](https://github.com/marola-dev/marola-site/pull/44) replaced it with Mapbox GL JS and added
the Windy-style layer rail; nothing under `site/static/vendor/` is Leaflet any more, and
`site/areas.json`'s `tiles`/`tiles_attribution` fields are vestigial for this repo
([reference](4-reference.md#area-fields)).
