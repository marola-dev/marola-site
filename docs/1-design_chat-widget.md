# The chat widget

`site/static/chatbot-config.js` and `chat.js` (MIP-0033 §5.2): a widget that stays hidden until it
finds a working endpoint, with no server dependency by default.

## How it behaves

`chat.js` reads `window.MAROLA_CHAT_ENDPOINT` from `chatbot-config.js`. Empty (the committed,
default state) and the script returns immediately: no toggle button, no request, so a fresh clone
never shows a chat button pointing nowhere. With an endpoint set, it calls `GET <endpoint>/health`
on page load and only reveals `#chat-toggle` on a 200. Opening the panel focuses the input; asking
a question posts `{"question": …}` to `POST <endpoint>/ask` and renders `.answer` from the JSON
body. A later failure while chatting — a timeout (30 s) or a non-OK response — shows the
`#chat-offline` message rather than hanging; `/health`'s own timeout is 4 s.

## Turning it on (from the app's own notes)

The widget's endpoint is the app's own chat server, exposed through a **named** Cloudflare Tunnel
(a quick/ephemeral tunnel's URL changes every restart, which would break the committed config).
The full walkthrough — Ollama setup, the server, the tunnel — is
[RUN-LOCALLY §5.2](https://docs.marola.dev/1-Using-marola/RUN-LOCALLY/#52-plug-your-local-model-into-the-public-sites-chat-widget-mip-0033),
in the umbrella: the commands below are its widget half.

```bash
# in a marola-app checkout
just run -- --serve-chat            # http://localhost:8787 — GET /health, POST /ask
cloudflared tunnel login             # one-time
cloudflared tunnel create marola-chat
cloudflared tunnel route dns marola-chat chat.<your-domain>
cloudflared tunnel run --url http://localhost:8787 marola-chat
```

Then, in this repo, edit `site/static/chatbot-config.js`:

```js
window.MAROLA_CHAT_ENDPOINT = "https://chat.<your-domain>"; // or the trycloudflare.com URL
```

`just site-build` copies `site/static/*` (including this file) into `site/dist/` as-is — there is
no deploy-time rewrite for this one, unlike `mapbox-config.js`. Leaving it empty is the default,
committed state. Turning it on narrowly overrides MIP-0005 §9's "no server" decision for the site:
the maintainer's own machine becomes a real, if intermittent, origin, so uptime is whatever that
machine and tunnel happen to be, by design (MIP-0033 §6).
