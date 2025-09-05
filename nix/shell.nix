{
  mkShellNoCC,
  bash,
  zig,
  zls,
  gnutar,
  xz,
  p7zip,
  nativeBuildInputs,
  buildInputs,
}:
mkShellNoCC {
  inherit nativeBuildInputs buildInputs;

  packages = [
    bash # required by zig-flake
    zig
    zls

    # `zig build release` dependencies
    gnutar
    xz
    p7zip
  ];
}
