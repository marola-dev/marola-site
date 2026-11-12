# The whole site as one Nix package: the Haskell server (back/server), the static pages (back/pages)
# and the Elm map page (front/). A function of pkgs' parts, for `pkgs.callPackage`, so
# piabrota/nix-os builds it with its own nixpkgs. The build has no network: the Haskell packages come
# from nixpkgs' Hackage set, the npm packages from front/package-lock.json (fetchNpmDeps), the Elm
# packages from nix/elm-srcs.nix and nix/registry.dat (`elm2nix snapshot` in front/), and
# MEMBERS.md from site/members/ (pinned by blob id in site/members.version).
{
  lib,
  stdenv,
  haskell,
  sqlite,
  elmPackages,
  fetchNpmDeps,
  fetchurl,
  npmHooks,
  nodejs,
}:
let
  root = ./..;
  # Only what the build reads. Build output (dist, front/dist, node_modules, elm-stuff,
  # dist-newstyle) stays out of the store path, so a local build and a clean checkout hash the same.
  keep =
    path: _type:
    let
      rel = lib.removePrefix (toString root + "/") (toString path);
    in
    builtins.match "(front|site|nix)(/.*)?|scripts|scripts/(site_build.sh|front_build.sh|site_fixtures.mjs)" rel != null
    && builtins.match "front/(node_modules|dist|elm-stuff)(/.*)?" rel == null
    && builtins.match "site/dist(/.*)?" rel == null;
  src = lib.cleanSourceWith {
    src = root;
    filter = keep;
  };

  # base >=4.18 && <4.19 in both .cabal files: GHC 9.6, as `just back-test` uses (9.6.6).
  hs = haskell.packages.ghc96.override {
    overrides = self: super: {
      # The system SQLite, not the copy direct-sqlite bundles (cabal.project's +systemlib), so a
      # security fix of SQLite is a nixpkgs update.
      direct-sqlite = lib.pipe super.direct-sqlite [
        (haskell.lib.compose.enableCabalFlag "systemlib")
        (haskell.lib.compose.addExtraLibrary sqlite)
      ];
      # Files.hs imports hIfNoneMatch from Network.HTTP.Types, which exports everything only from
      # http-types 0.12.5 (nixpkgs has 0.12.4); cabal.project.freeze pins 0.12.6.
      http-types = lib.pipe super.http-types [
        (haskell.lib.compose.overrideSrc {
          version = "0.12.6";
          src = fetchurl {
            url = "https://hackage.haskell.org/package/http-types-0.12.6/http-types-0.12.6.tar.gz";
            hash = "sha256-togEKstOU/H17+0mBWzx/cOuXca4XPvjIe3/wwecEGw=";
          };
        })
        haskell.lib.compose.dontCheck
      ];
      # The tests read the repo's site/ tree, which the package's own source does not hold:
      # `just back-test` runs them.
      marola-pages = haskell.lib.compose.dontCheck (self.callCabal2nix "marola-pages" (lib.cleanSource ../back/pages) { });
      marola-server = haskell.lib.compose.dontCheck (self.callCabal2nix "marola-server" (lib.cleanSource ../back/server) { });
    };
  };
  pages = haskell.lib.compose.justStaticExecutables hs.marola-pages;
  server = haskell.lib.compose.justStaticExecutables hs.marola-server;
in
stdenv.mkDerivation {
  pname = "marola-site";
  version = "0.1.0";
  inherit src;

  npmRoot = "front";
  npmDeps = fetchNpmDeps {
    name = "marola-site-npm-deps";
    src = "${src}/front";
    hash = "sha256-w1usWi2q30ak6rTl95N+nu1yVqS3hr4VkKgukMdKtJ4=";
  };

  nativeBuildInputs = [
    nodejs
    npmHooks.npmConfigHook
    elmPackages.elm
  ];

  # vite-plugin-elm runs `elm make`, which reads its packages from ELM_HOME; fetchElmDeps sets
  # ELM_HOME and fills it, so elm never asks package.elm-lang.org.
  postConfigure = elmPackages.fetchElmDeps {
    elmPackages = import ./elm-srcs.nix;
    elmVersion = elmPackages.elm.version;
    registryDat = ./registry.dat;
  };

  # front/elm.json names 0.19.1, the official release CI uses. nixos-unstable ships a 0.19.2 build,
  # which refuses that elm.json, and nixos-26.05 (piabrota/nix-os) ships 0.19.1: the build's copy
  # names the version of the elm it builds with. elm make also verifies test-dependencies and the
  # build never compiles front/tests/: drop them, so nix/elm-srcs.nix needs no elm-explorations/test.
  postPatch = ''
    patchShebangs scripts
    node -e '
      const fs = require("fs");
      const j = JSON.parse(fs.readFileSync("front/elm.json", "utf8"));
      j["elm-version"] = "${elmPackages.elm.version}";
      j["test-dependencies"] = { direct: {}, indirect: {} };
      fs.writeFileSync("front/elm.json", JSON.stringify(j, null, 4) + "\n");
    '
  '';

  # npmConfigHook has installed front/node_modules; site_build.sh skips `npm ci` and cabal.
  buildPhase = ''
    runHook preBuild
    MAROLA_PAGES_BIN=${pages}/bin/marola-pages MAROLA_SERVER_BIN=${server}/bin/marola-server \
      bash scripts/site_build.sh --no-install
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/marola
    ln -s ${server}/bin/marola-server $out/bin/marola-server
    cp -r dist $out/share/marola/dist
    runHook postInstall
  '';

  passthru = { inherit pages server; };

  meta = {
    description = "marola.dev: the swim map, its static pages and its Haskell server";
    homepage = "https://marola.dev";
    mainProgram = "marola-server";
  };
}
