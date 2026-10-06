# The pool node's proxy (compose.yml): tinyproxy, plus curl and jq for `just br-proxy-node check`.
FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
RUN apk add --no-cache tinyproxy curl jq
USER nobody
# -d: in the foreground, logging to stdout (docker compose logs tinyproxy).
ENTRYPOINT ["tinyproxy", "-d", "-c", "/etc/tinyproxy/tinyproxy.conf"]
