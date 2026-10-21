# The pool node's proxy (compose.yml): proxy/, built and tested here, plus curl and jq for `just br-proxy-node check`.
FROM rust:1.99.1-alpine3.22@sha256:2b3b5cdd9112f19366d21b94541ffcd3d58bf838f696451a0d50c8032088cb15 AS build
WORKDIR /src
COPY proxy/ .
RUN cargo test --release --locked && cargo build --release --locked

FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
RUN apk add --no-cache curl jq
COPY --from=build /src/target/release/br-proxy /usr/local/bin/br-proxy
USER nobody
ENTRYPOINT ["br-proxy"]
