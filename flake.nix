{
  description = "marola-front — the static map at marola.dev (MIP-0070)";

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
        # The whole site as one offline Nix build (server, static pages, Fable client): docs/5-hosting.md.
        packages.default = package;
        checks.package = package;

        # Docker is the host's, as in every marola repo: `just site-build` runs the pinned app image.
        devShells.default = pkgs.mkShell {
          name = "marola-front";
          packages = [ pkgs.nodejs pkgs.dotnet-sdk_10 pkgs.fable pkgs.fantomas ] ++ devkit.tools;
          shellHook = devkit.shellHook + ''
            # Nothing leaves the box but NuGet package downloads; the caches live in the temp dir.
            export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
            export DOTNET_CLI_HOME="''${TMPDIR:-/tmp}/dotnet" NUGET_PACKAGES="''${TMPDIR:-/tmp}/nuget"
            git config core.hooksPath .devkit/.githooks 2>/dev/null || true
            echo "marola-front dev shell. Run 'just' to see available commands."
          '';
        };
      });
}
