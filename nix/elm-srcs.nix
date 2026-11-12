# The Elm packages front/elm.json names (direct and indirect, not the test ones), for
# elmPackages.fetchElmDeps in nix/package.nix: the format `elm2nix convert` writes. Each sha256 is the
# hash of https://github.com/<name>/archive/<version>.tar.gz. They are lib.fakeHash placeholders
# until a machine with network runs `nix build .#default` and copies each hash Nix reports (or runs
# `elm2nix convert` in front/). Rewrite this file after a change to front/elm.json.
let
  fake = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
in
{
  "elm/browser" = { sha256 = fake; version = "1.0.2"; };
  "elm/core" = { sha256 = fake; version = "1.0.5"; };
  "elm/html" = { sha256 = fake; version = "1.0.0"; };
  "elm/json" = { sha256 = fake; version = "1.1.3"; };
  "elm/svg" = { sha256 = fake; version = "1.0.1"; };
  "elm/time" = { sha256 = fake; version = "1.0.0"; };
  "elm/url" = { sha256 = fake; version = "1.0.0"; };
  "elm/virtual-dom" = { sha256 = fake; version = "1.0.3"; };
}
