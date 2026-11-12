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
