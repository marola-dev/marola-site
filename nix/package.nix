# The whole site as one Nix package: the .NET server, the static pages and the Fable client.
# A function of pkgs' parts, for `pkgs.callPackage`, so piabrota/nix-os builds it with its own nixpkgs.
# The build has no network: NuGet packages come from nix/deps.json (`just nix-deps`), Fable from
# nixpkgs, and MEMBERS.md from site/members/ (pinned by blob id in site/members.version).
{
  lib,
  buildDotnetModule,
  dotnetCorePackages,
  fable,
  nodejs,
}:
let
  # Only what the build reads. The dev trees (bin, obj, out, dist) are build output and stay out of
  # the store path, so a local build and a clean checkout hash the same.
  root = ./..;
  keep =
    path: _type:
    let
      rel = lib.removePrefix (toString root + "/") (toString path);
    in
    builtins.match "(app|site)(/.*)?|scripts|scripts/(app_build.sh|app_fixtures.mjs)" rel != null
    && builtins.match "app/.*/(bin|obj|out)(/.*)?" rel == null
    && builtins.match "(app/dist|site/dist)(/.*)?" rel == null;
in
buildDotnetModule {
  pname = "marola-site";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = root;
    filter = keep;
  };

  # The server is the only project published. The page builder and the Fable client are listed as test
  # projects because that is the nixpkgs way to restore (and so fetch-deps to lock) a project that is
  # built but not installed: scripts/app_build.sh runs both in postBuild.
  projectFile = "app/Server/Marola.Server.fsproj";
  testProjectFile = [
    "app/Pages.Build/Marola.Pages.Build.fsproj"
    "app/Client/App/Marola.Client.App.fsproj"
  ];
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;

  executables = [ "marola-server" ];

  nativeBuildInputs = [
    fable
    nodejs
  ];

  DOTNET_CLI_TELEMETRY_OPTOUT = "1";
  DOTNET_NOLOGO = "1";

  # Every restore here is unlocked, so packages.lock.json is not checked in this build, on purpose:
  # the nixpkgs restore passes --runtime (a locked restore then fails with NU1004), and Nix repacks
  # each nupkg without its signature, so NuGet's content hash check against the lock file fails
  # (NU1403). Here the hashes in nix/deps.json pin every package; the lock files stay enforced by
  # `just app-test` and `just quality`.
  RestoreLockedMode = "false";

  # Fable output, the static pages (MEMBERS.md from site/members/) and the vendor files, into app/dist.
  postBuild = ''
    bash scripts/app_build.sh
    # Fable's project cache: no page loads it, and it holds the random name of the build's NuGet
    # folder, so two builds of the same source would differ by this one file.
    rm app/dist/app/fable_modules/project_cracked.json
  '';

  postInstall = ''
    mkdir -p $out/share/marola
    cp -r app/dist $out/share/marola/dist
  '';

  meta = {
    description = "marola.dev: the static swim map and its .NET server";
    homepage = "https://marola.dev";
    mainProgram = "marola-server";
  };
}
