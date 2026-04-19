{
  lib,
  stdenv,
  callPackage,
  installShellFiles,
  zig,
  releaseMode ? "safe",
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
      ../lib
      ../build.zig
      ../build.zig.zon
    ];
  };

  nativeBuildInputs = [
    installShellFiles
    zig
  ];

  dontInstall = true;
  doCheck = true;

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

  checkPhase = ''
    zig build test \
      --system $PACKAGE_DIR \
      -Dversion-string=${finalAttrs.version} \
      --color off
  '';

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
