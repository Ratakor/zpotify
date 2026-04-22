{
  mkShellNoCC,
  zig,
  zls,
  jq,
  zon2nix,
  gnutar,
  xz,
  p7zip,
}:
mkShellNoCC {
  packages = [
    zig
    zls
    jq
    zon2nix

    # `zig build release` dependencies
    gnutar
    xz
    p7zip
  ];
}
