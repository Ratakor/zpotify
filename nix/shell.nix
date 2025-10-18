{
  mkShellNoCC,
  zig,
  zls,
  jq,
  gnutar,
  xz,
  p7zip,
}:
mkShellNoCC {
  packages = [
    zig
    zls
    jq

    # `zig build release` dependencies
    gnutar
    xz
    p7zip
  ];
}
