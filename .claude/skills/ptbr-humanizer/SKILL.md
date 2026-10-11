---
name: ptbr-humanizer
description: Use when writing or reviewing any Portuguese (pt-BR) a visitor reads on marola.dev — site/i18n/pt-BR.json, the pt-BR articles in about.html and support.html, meta descriptions — so it reads like a Brazilian wrote it, not a translation or a model
---

# ptbr-humanizer: pt-BR that sounds like a person from here

## Overview

marola's Portuguese started as translations of English copy, and it shows: "o que é isto",
"quadro" for the board, "dados em si", em dashes everywhere. Visitors are Brazilian swimmers and
volunteers; the copy should sound like a friendly, precise public-information site (think a
municipal beach bulletin written by someone who swims), not like a product page or a translator.

## Where the Portuguese lives

- `site/i18n/pt-BR.json`: every string the page and `app.js` render. Edit it, then
  `python3 scripts/i18n_bundle.py` (never edit `site/static/i18n.js`). `site/i18n/context.json`
  says where each key appears.
- The `lang="pt-BR"` articles in `about.html` and `support.html`, and each page's
  `<meta name="description">`.
- The fallback text inside `data-i18n` elements in the HTML must match the catalog (first paint).

## Rules

1. **Say it the way people say it.** "o que é o marola", not "o que é isto"; "melhor horário",
   not "melhor hora por"; "à noite", not "escuro"; "dá para conferir", not "podem ser conferidos".
2. **Name things concretely.** "os dados das praias", "o laudo de balneabilidade", "a pontuação";
   never "o quadro", "a camada de inteligência", "a solução".
3. **No em dash.** Use a period, a colon, a semicolon or a comma; "·" only in compact metadata,
   at most once per line. The same goes for the English catalog.
4. **Short sentences, active voice, você.** Split anything over ~25 words. Prefer "usamos" or the
   subject the visitor knows over passive "é registrado".
5. **No marketing or AI words**: inteligente, revolucionário, perfeito, solução, jornada,
   potencializar, "com IA", emoji.
6. **Keep what is data or a name**: PRÓPRIA/IMPRÓPRIA (the agency's verdict, verbatim), provider
   names (Open-Meteo, OpenStreetMap, IMA/SC), beach names, units with a no-break space.
7. **House style is lowercase** in the catalog (the CSS lowercases anyway); `site_check.js` fails
   uppercase outside its allowlist.
8. **ICU placeholders stay intact**: `{n, plural, ...}`, `{x, select, ...}`; read the pt-BR output
   for each branch, not just the template.
9. **Trust and honesty over polish**: say what is not available yet ("em breve", "ainda não
   publicamos") instead of hiding it.

## Process

1. Read the English string and `context.json` for the key, then write the Portuguese from the
   meaning, not word by word.
2. Read it aloud in your head as a carioca or a manezinho would; if it sounds dubbed, rewrite.
3. Rebuild the bundle, run `node scripts/site_check.js` and update the needles it holds for the
   strings you changed (they are pt-BR on purpose: they pin the visible copy).
4. Screenshot the pt-BR page at 390 px: longer strings must still fit their pills and rows.
