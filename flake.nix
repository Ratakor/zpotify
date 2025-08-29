{
  description = "A CLI/TUI for Spotify";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    zig = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      # https://github.com/zigtools/zls/pull/2469
      url = "github:Ratakor/zls/older-versions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-flake.follows = "zig";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    zig,
    zls,
    ...
  }: let
    forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
  in {
    devShells = forAllSystems (system: pkgs: {
      default = pkgs.mkShellNoCC {
        inherit (self.packages.${system}.default) nativeBuildInputs buildInputs;

        packages = with pkgs; [
          git
          bash
          zig.packages.${system}.zig_0_15_1
          zls.packages.${system}.zls_0_15_0

          # `zig build release` dependencies
          gnutar
          xz
          p7zip
        ];
      };
    });

    packages = forAllSystems (system: pkgs: {
      default = zig.packages.${system}.zig_0_15_1.makePackage {
        pname = "zpotify";
        version = "0.4.0-dev";

        src = ./.;
        zigReleaseMode = "fast";
        # depsHash = "<replace this with the hash Nix provides in its error message>"

        nativeBuildInputs = with pkgs; [
          pkg-config
        ];

        buildInputs = with pkgs; [
          glib
          chafa
          libjpeg
        ];

        meta = with pkgs.lib; {
          description = "A CLI/TUI for Spotify";
          homepage = "https://github.com/ratakor/zpotify";
          license = licenses.gpl3Plus;
          mainProgram = "zpotify";
        };
      };
    });
  };
}
