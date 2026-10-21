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
      in
      {
        # Docker is the host's, as in every marola repo: `just site-build` runs the pinned app image.
        devShells.default = pkgs.mkShell {
          name = "marola-site";
          # cargo and friends build ops/br-proxy/proxy (ADR-0002); picasso's labs/rust-agent (h0ffmann/picasso#142) replaces them once merged.
          packages = [ pkgs.nodejs pkgs.cargo pkgs.rustc pkgs.clippy pkgs.rustfmt ] ++ devkit.tools;
          shellHook = devkit.shellHook + ''
            git config core.hooksPath .devkit/.githooks 2>/dev/null || true
            echo "marola-site dev shell. Run 'just' to see available commands."
          '';
        };
      });
}
