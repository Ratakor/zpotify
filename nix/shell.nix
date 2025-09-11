{
  mkShellNoCC,
  bash,
  zig,
  zls,
  gnutar,
  xz,
  p7zip,
  pkg-config,
  glib,
  chafa,
  libjpeg,
}:
mkShellNoCC {
  packages = [
    zig
    zls

    # `zig build release` dependencies
    gnutar
    xz
    p7zip
  ];

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    glib
    chafa
    libjpeg
  ];
}
