{
  lib,
  stdenv,
  callPackage,
  installShellFiles,
  zig,
}:
let
  fs = lib.fileset;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zpotify";
  inherit (import ./version.nix lib) version;

  src = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../src
      ../vendor
      ../build.zig
      ../build.zig.zon
    ];
  };

  deps = callPackage ./deps.nix { };

  zigBuildFlags = [
    "--system"
    "${finalAttrs.deps}"
    # "--release=fast"
    "-Dversion-string=${finalAttrs.version}"
  ];

  nativeBuildInputs = [
    installShellFiles
    zig.hook
  ];

  postInstall = ''
    installShellCompletion --cmd zpotify \
      --bash <($out/bin/zpotify completion bash) \
      --zsh <($out/bin/zpotify completion zsh)
  '';

  meta = {
    description = "CLI/TUI for Spotify";
    homepage = "https://github.com/ratakor/zpotify";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.ratakor ];
    mainProgram = "zpotify";
  };
})
