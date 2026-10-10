#!/usr/bin/env bash
# Write <dist>/contact-config.js from WEB3FORMS_ACCESS_KEY (site.yml, at deploy; #119).
#
#   WEB3FORMS_ACCESS_KEY=<uuid> scripts/contact_config.sh site/dist
#   scripts/contact_config.sh --self-test
#
# Web3Forms' access key is public by design (it only lets someone send mail to marola's inbox),
# but it still lives in a repo variable, not the repo. No key keeps the committed empty config and
# contact.html says the form is not connected; the deploy goes on.
set -euo pipefail

write() {
  local dist="$1" key="${WEB3FORMS_ACCESS_KEY:-}"
  [ -d "$dist" ] || { echo "contact_config: no $dist — build the site first" >&2; exit 1; }
  if [ -z "$key" ]; then
    echo "::warning::contact_config: WEB3FORMS_ACCESS_KEY is not set, so contact.html says the form is not connected" >&2
  elif ! [[ "$key" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    echo "contact_config: WEB3FORMS_ACCESS_KEY is not a Web3Forms access key (a UUID)" >&2; exit 1
  fi
  printf '// written by scripts/contact_config.sh at deploy\nwindow.MAROLA_CONTACT = { accessKey: "%s" };\n' \
    "$key" >"$dist/contact-config.js"
  echo "contact_config: wrote $dist/contact-config.js (key $([ -n "$key" ] && echo set || echo none))" >&2
}

self_test() {
  local t f=0
  t="$(mktemp -d)"; trap 'rm -rf "$t"' RETURN
  run() { env -u WEB3FORMS_ACCESS_KEY "$@" bash "${BASH_SOURCE[0]}" "$t" 2>/dev/null; }
  run WEB3FORMS_ACCESS_KEY=0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123 || { echo "FAIL: a UUID key"; f=1; }
  grep -qx 'window.MAROLA_CONTACT = { accessKey: "0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123" };' "$t/contact-config.js" \
    || { echo "FAIL: the config does not carry the key"; f=1; }
  run WEB3FORMS_ACCESS_KEY='x"; alert(1); "' && { echo "FAIL: a key with quotes was written"; f=1; }
  grep -qF 'alert' "$t/contact-config.js" && { echo "FAIL: a bad key reached the file"; f=1; }
  run WEB3FORMS_ACCESS_KEY=not-a-key && { echo "FAIL: a key that is not a UUID was written"; f=1; }
  run || { echo "FAIL: no key should warn, not fail"; f=1; }
  grep -q 'accessKey: ""' "$t/contact-config.js" || { echo "FAIL: no key should leave it empty"; f=1; }
  echo "contact_config self-test:" "$([ "$f" -eq 0 ] && echo ok || echo FAILED)"
  [ "$f" -eq 0 ]
}

case "${1:-}" in
  --self-test) self_test ;;
  "" | -*) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  *) write "$1" ;;
esac
