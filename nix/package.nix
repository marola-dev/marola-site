# The whole site as one Nix package: the Haskell server (back/server), the static pages (back/pages)
# and the Elm map page (front/). A function of pkgs' parts, for `pkgs.callPackage`, so
# piabrota/nix-os builds it with its own nixpkgs. The build has no network: the Haskell packages come
# from nixpkgs' Hackage set, the npm packages from front/package-lock.json (fetchNpmDeps), the Elm
# packages from nix/elm-srcs.nix and nix/registry.dat (elm 0.19.1's own package registry, copied
# from an ELM_HOME that built front/), and MEMBERS.md from site/members/ (pinned by
# blob id in site/members.version).
#
# Unverified: this file was written where Nix could not fetch its inputs. npmDepsHash and the
# hashes in nix/elm-srcs.nix are lib.fakeHash placeholders; the first `nix build .#default` with
# network reports each real hash. Whether nixpkgs' versions of the Haskell dependencies fall inside
# the bounds of the two .cabal files is not checked either (cabal.project.freeze pins the versions
# `just back-test` uses; callCabal2nix does not read it).
{
  lib,
  stdenv,
  haskell,
  sqlite,
  elmPackages,
  fetchNpmDeps,
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
    hash = lib.fakeHash;
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
    elmVersion = "0.19.1";
    registryDat = ./registry.dat;
  };

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
