{
  lib,
  stdenvNoCC,
  callPackage,
  installShellFiles,
  zig,
  releaseMode ? "safe",
}:
let
  fs = lib.fileset;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zpotify";
  inherit (import ./version.nix lib) version;

  src = fs.toSource {
    root = ../.;
    fileset = fs.unions [
      ../src
      ../lib
      ../build.zig
      ../build.zig.zon
    ];
  };

  nativeBuildInputs = [
    installShellFiles
    zig
  ];

  configurePhase = ''
    export ZIG_GLOBAL_CACHE_DIR=$TEMP/.cache
    PACKAGE_DIR=${callPackage ./deps.nix { }}
  '';

  buildPhase = ''
    zig build install \
      --system $PACKAGE_DIR \
      --release=${releaseMode} \
      -Dversion-string=${finalAttrs.version} \
      --color off \
      --prefix $out
  '';

  doCheck = true;
  checkPhase = ''
    zig build test \
      --system $PACKAGE_DIR \
      -Dversion-string=${finalAttrs.version} \
      --color off
  '';

  dontInstall = true;
  postBuild = ''
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
