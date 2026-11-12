{
  description = "marola-site — the static map at marola.dev (MIP-0070)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Tools, the just module and the lint toolchain. Bump with .github/workflows/*.yml's @tag.
    marola-devkit = {
      url = "github:marola-dev/marola-devkit/v0.20.4";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, marola-devkit }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        devkit = marola-devkit.lib.${system};
        package = pkgs.callPackage ./nix/package.nix { };
        # ormolu 0.7.7.0, the version `just back-fmt` is written for: nixpkgs has 0.7.4 (GHC 9.6) and
        # 0.8, and 0.7.7.0 needs ghc-lib-parser 9.10, which GHC 9.10's package set pairs with Cabal-syntax 3.12.
        ormolu = pkgs.haskell.lib.compose.justStaticExecutables (pkgs.haskell.packages.ghc910.override {
          overrides = self: super: {
            ghc-lib-parser = pkgs.haskell.lib.compose.overrideSrc {
              version = "9.10.3.20250912";
              src = pkgs.fetchurl {
                url = "https://hackage.haskell.org/package/ghc-lib-parser-9.10.3.20250912/ghc-lib-parser-9.10.3.20250912.tar.gz";
                hash = "sha256-+XwStkzua7uCc+55RtN6bV3NO8HDWZpm+Lv9bcVBkMY=";
              };
            } super.ghc-lib-parser;
            ormolu = pkgs.lib.pipe (super.ormolu.override { Cabal-syntax = self.Cabal-syntax_3_12_1_0; }) [
              (pkgs.haskell.lib.compose.overrideSrc {
                version = "0.7.7.0";
                src = pkgs.fetchurl {
                  url = "https://hackage.haskell.org/package/ormolu-0.7.7.0/ormolu-0.7.7.0.tar.gz";
                  hash = "sha256-2pbNfIJlOQ8Mwsudvws7QpiAPDfM3ezqVxjvRtmRyYA=";
                };
              })
              pkgs.haskell.lib.compose.doJailbreak
              pkgs.haskell.lib.compose.dontCheck
            ];
          };
        }).ormolu;
      in
      {
        # The whole site as one offline Nix build (Haskell server, static pages, Elm page): docs/5-hosting.md.
        packages.default = package;
        checks.package = package;

        # Docker is the host's, as in every marola repo: `just site-build` runs the pinned app image.
        devShells.default = pkgs.mkShell {
          name = "marola-site";
          # GHC 9.6 is what the .cabal files' base bound and cabal.project.freeze (made with 9.6.6) need.
          packages = [
            pkgs.nodejs
            pkgs.elmPackages.elm
            pkgs.haskell.compiler.ghc96
            pkgs.cabal-install
            ormolu
            pkgs.shellcheck
            pkgs.pkg-config
            pkgs.sqlite
            pkgs.zlib
          ] ++ devkit.tools;
          shellHook = devkit.shellHook + ''
            git config core.hooksPath .devkit/.githooks 2>/dev/null || true
            echo "marola-site dev shell. Run 'just' to see available commands."
          '';
        };
      });
}
