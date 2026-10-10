#!/usr/bin/env bash
# Cache-bust the built site so index.html and app.js/style.css can never be served from two
# different builds (fix/site-smoke-panel-null).
set -euo pipefail

dist="${1:-site/dist}"
index="$dist/index.html"
[ -f "$index" ] || { echo "stamp_site_version: no $index — build the site first" >&2; exit 1; }

version="$(git rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"

# about.html, support.html, news.html and contact.html load the same catalog (i18n.js), so they are stamped too.
for page in "$index" "$dist/about.html" "$dist/support.html" "$dist/news.html" "$dist/contact.html"; do
  [ -f "$page" ] || continue
  sed -i -E \
    -e "s#(href=\"style\.css)\"#\\1?v=${version}\"#" \
    -e "s#(href=\"vendor/mapbox-gl\.css)\"#\\1?v=${version}\"#" \
    -e "s#(src=\"vendor/mapbox-gl-csp\.js)\"#\\1?v=${version}\"#" \
    -e "s#(src=\"(app|ui|i18n|flow|mapbox-config|contact|contact-config)\.js)\"#\\1?v=${version}\"#" \
    "$page"
  echo "stamped $page with ?v=$version"
done
