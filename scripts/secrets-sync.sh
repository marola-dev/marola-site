#!/usr/bin/env bash
# Copy this repo's GitHub Actions secrets from 1Password (vault marola-ci) to GitHub.
# 1Password is the source of truth: a value edited on GitHub is overwritten on the next run.
# Usage: scripts/secrets-sync.sh [--dry-run]   (docs/3-development.md#secrets-and-1password)
#
# Needs: bash >= 4; op, the 1Password CLI v2, signed in (app integration or `op signin`);
# gh signed in with admin on marola-dev/marola-site (in `nix develop`).
set -euo pipefail

repo=marola-dev/marola-site
vault=marola-ci
# MAROLA_BR_PROXY is left out: an emergency override, normally unset (site.yml).
secrets=(
  CLOUDFLARE_API_TOKEN
  CLOUDFLARE_ACCOUNT_ID
  MAPBOX_PUBLIC_TOKEN
  TAILSCALE_OAUTH_CLIENT_ID
  TAILSCALE_OAUTH_SECRET
  MAROLA_CROSS_REPO_PAT
  RJ_MAROLA_INSTAGRAM
  FL_MAROLA_INSTAGRAM
)

dry=false
case "${1:-}" in
  "") ;;
  --dry-run) dry=true ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

for cmd in op gh; do
  command -v "$cmd" >/dev/null || { echo "secrets-sync: '$cmd' not on PATH" >&2; exit 1; }
done
op --version | grep -q '^2\.' || { echo "secrets-sync: needs op v2, found $(op --version)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "secrets-sync: gh is not signed in: gh auth login" >&2; exit 1; }
op vault get "$vault" >/dev/null || { echo "secrets-sync: op cannot read vault '$vault'" >&2; exit 1; }

# Read everything first: a missing item must stop the run before any secret is written,
# or gh would store an empty value from the failed pipe.
declare -A values
for name in "${secrets[@]}"; do
  values[$name]="$(op read --no-newline "op://$vault/$name/credential")"
  [[ -n "${values[$name]}" ]] || { echo "secrets-sync: $name is empty in $vault" >&2; exit 1; }
  echo "read $name" >&2
done
$dry && exit 0

for name in "${secrets[@]}"; do
  # printf is a builtin: the value never shows up as a process argument.
  printf '%s' "${values[$name]}" | gh secret set "$name" --repo "$repo"
  echo "set $name" >&2
done
