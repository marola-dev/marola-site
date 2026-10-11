#!/usr/bin/env bash
# One-time setup of an Ubuntu (or Debian) machine for this repo: Determinate Nix, then the
# 1Password app and CLI from 1Password's apt repository, then the nix-config submodule (the
# maintainer's Nix labs: ai-jail, Claude Code, OpenCode). Safe to re-run: a step already done is
# skipped. --dry-run prints what it would run. docs/3-development.md#for-ubuntu-users
set -euo pipefail

dry=false
case "${1:-}" in
  "") ;;
  --dry-run) dry=true ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

run() {
  if $dry; then printf '+ %s\n' "$*" >&2; else bash -c "$1"; fi
}

# shellcheck source=/dev/null
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" ubuntu "*|*" debian "*) ;;
  *) echo "setup-ubuntu: this is ${PRETTY_NAME:-not Ubuntu}; see docs/3-development.md" >&2; exit 1 ;;
esac

if command -v nix >/dev/null; then
  echo "nix: already installed ($(nix --version))" >&2
else
  echo "nix: installing Determinate Nix (flakes on by default)" >&2
  run "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
fi

# Not from Nix: the desktop app only talks to an op owned by the onepassword-cli group with
# setgid, which a binary in the Nix store cannot be.
if command -v op >/dev/null && dpkg -s 1password >/dev/null 2>&1; then
  echo "1password: app and CLI already installed (op $(op --version))" >&2
else
  echo "1password: adding 1Password's apt repository and installing the app and CLI" >&2
  arch=$(dpkg --print-architecture)
  key=https://downloads.1password.com/linux/keys/1password.asc
  run "curl -sS $key | sudo gpg --yes --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg"
  run "echo 'deb [arch=$arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$arch stable main' | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null"
  run "sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ /usr/share/debsig/keyrings/AC2D62742012EA22"
  run "curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null"
  run "curl -sS $key | sudo gpg --yes --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg"
  run "sudo apt-get update && sudo apt-get install -y 1password 1password-cli"
fi

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
if [ -e "$repo/nix-config/flake.nix" ]; then
  echo "nix-config: submodule already checked out" >&2
else
  echo "nix-config: checking out the submodule" >&2
  run "git -C '$repo' submodule update --init --depth 1 nix-config"
fi

cat >&2 <<'NEXT'

Done. What is left is yours, in the 1Password app (once):
  1. Sign in (or create the account at https://1password.com).
  2. Settings > Security: turn on "Unlock using system authentication".
  3. Settings > Developer: turn on "Integrate with 1Password CLI".
  4. Check it from a new terminal: op vault list
Then: nix develop, gh auth login, just secrets-sync --dry-run (docs/3-development.md).
Claude Code in ai-jail: just -f nix-config/labs/agentic/justfile jco (op does not work inside it).
NEXT
