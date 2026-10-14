# Ponytail scan of the JavaScript

A scan for over-engineering in marola-site's hand-written JavaScript, made with Ponytail's
`ponytail-audit` skill. Ponytail is Dietrich Gebert's Claude Code plugin (MIT,
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)). This repository declares it
in `.claude/settings.json` at `v5.2.0`. The scan used the skill as h0ffmann/ww3-gpu vendors it, at
commit `bd6176a9b33ab72594ff82e6f34f17b085f25565`, on marola-site at `c231a68`, on 2026-10-14.

The scan only reports. Nothing below is changed yet. Bugs, security, performance, the CSP,
accessibility and the i18n mechanism were outside its scope.

## The files

| File | Lines |
|---|---|
| `site/static/app.js` | 840 |
| `site/static/ui.js` | 176 |
| `site/static/chat.js` | 84 |
| `site/static/flow.js` | 298 |
| `site/static/chatbot-config.js` | 2 |
| `site/static/mapbox-config.js` | 3 |
| `scripts/site_check.js` | 1165 |
| `scripts/redirect_check.js` | 43 |
| total | 2611 |

`site/static/i18n.js` is generated and `site/static/vendor/` is third-party, so neither was scanned.

## Findings

Ranked by the lines each would remove. The tag is the skill's own: `delete`, `stdlib`, `yagni`,
`shrink`.

| # | Where | Tag | Sure? | Lines | Simplification |
|---|---|---|---|---|---|
| 1 | `scripts/site_check.js:183-219` | delete | certain | -14 | The AudioContext stub fakes parts app.js never calls (biquad filter, oscillator, buffer, modulators). Keep gain, buffer source, `decodeAudioData` and `resume` |
| 2 | `scripts/site_check.js:721-728, 795-803, 821` | shrink | certain | -6 | Three loops re-read the same pages and re-extract the nav. Fold them into the `PAGES` loop |
| 3 | `site/static/app.js:63-69` | shrink | certain | -6 | `colour()` repeats the thresholds of `band()`. Use `getCss('--' + band(score, unfit))` |
| 4 | `site/static/chat.js:38-42` | shrink | certain | -4 | The pending bubble re-implements `addMessage`. Let `addMessage` return its element |
| 5 | `scripts/site_check.js:786-791` | shrink | certain | -3 | `site.yml` is read three more times. Use the already loaded `SITE_YML` in one loop |
| 6 | `scripts/site_check.js:729-730, 735-736, 755-756` | shrink | certain | -3 | "Loads only i18n.js and ui.js" is written three times. Use one loop |
| 7 | `site/static/app.js:100, 404-408` | stdlib | certain | -3 | Two hand loops look up an hour. Use `beach.hours.find(x => x.h === h) \|\| null` |
| 8 | `site/static/chat.js:17-25` | yagni | worth a look | -3 | Two timeouts and `checkHealth()` are used once each. Inline them |
| 9 | `scripts/site_check.js:128-129` | delete | certain | -2 | A comment about a "smoke" panel that no longer exists |
| 10 | `site/static/app.js:449-453` | shrink | worth a look | -2 | `trailColour` as one lookup |
| 11 | `scripts/site_check.js:754` | delete | certain | -1 | `const SUPPORT` re-reads `support.html` and shadows the same constant at line 23 |
| 12 | `site/static/app.js:573, 589, 631` | shrink | worth a look | -1 | The water-condition ternary chain written three times. One lookup object |
| 13 | `scripts/site_check.js` (15 places) | shrink | certain | 0 | `Object.assign(btn(k), { closest() … })` adds a method the stub already has. Four `JSON.parse(JSON.stringify(…))` can be `structuredClone` |
| 14 | `site/static/app.js:219, 511, 513` | shrink | worth a look | 0 | Guards against events Mapbox always supplies |

Total: about **-48 lines and no dependency removed**.

**The owner's call, not counted above.** `chat.js`, `chatbot-config.js` and the `#chat-*` markup
make a widget that does nothing on the live site: `MAROLA_CHAT_ENDPOINT` is empty in the
repository and no deploy step fills it, so `chat.js` returns at line 6. Removing it would take
about 86 lines of JavaScript and its markup. Whether to keep it is a MIP-0033 decision.

**Nothing to cut.** `flow.js`, `ui.js` (outside the i18n mechanism), `chatbot-config.js`,
`mapbox-config.js` and `redirect_check.js`. Two things in `site_check.js` stay on purpose: the
Keccak and EIP-55 code (Node's crypto has no Keccak-256), and the JSON-Schema validator, which
mirrors BoardSpec with no dependency.
