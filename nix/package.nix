{
  lib,
  zigPlatform,
  installShellFiles,
  pkg-config,
  glib,
  chafa,
  libjpeg,
}: let
  fs = lib.fileset;
in
  zigPlatform.makePackage {
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

    zigReleaseMode = "safe";
    depsHash = "sha256-jOcxZL2o/fgn5IMRpF4NwyxSEX6n2oSdacnBJVs7BgY=";

    nativeBuildInputs = [
      installShellFiles
      pkg-config
    ];

    buildInputs = [
      glib # chafa dependency
      chafa
      libjpeg
    ];

    postInstall = ''
      installShellCompletion --cmd zpotify \
        --zsh <($out/bin/zpotify completion zsh)
    '';

    meta = {
      description = "CLI/TUI for Spotify";
      homepage = "https://github.com/ratakor/zpotify";
      license = lib.licenses.gpl3Plus;
      maintainers = [lib.maintainers.ratakor];
      mainProgram = "zpotify";
    };
  }
