{
  lib,
  stdenv,
  callPackage,
  installShellFiles,
  pkg-config,
  zig,
  glib,
  chafa,
  libjpeg,
  image-support ? true,
}:
let
  fs = lib.fileset;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "zpotify";
  # Must match the `version` in `build.zig.zon`.
  version = "0.4.0-dev";

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
    "-Dimage-support=${lib.boolToString image-support}"
  ];

  nativeBuildInputs = [
    installShellFiles
    pkg-config
    zig.hook
  ];

  buildInputs = lib.optionals image-support [
    glib # chafa dependency
    chafa
    libjpeg
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
