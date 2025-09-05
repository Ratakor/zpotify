{
  description = "CLI/TUI for Spotify";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zig = {
      url = "github:silversquirl/zig-flake/compat";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      url = "github:zigtools/zls/0.15.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig";
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
    packages = forAllSystems (system: pkgs: {
      default = self.packages.${system}.zpotify;
      zpotify = pkgs.callPackage ./nix/package.nix {
        zigPlatform = zig.packages.${system}.zig_0_15_1;
      };
    });

    devShells = forAllSystems (system: pkgs: {
      default = pkgs.callPackage ./nix/shell.nix {
        zig = zig.packages.${system}.zig_0_15_1;
        zls = zls.packages.${system}.default;
        # https://github.com/NixOS/nixpkgs/pull/438854
        # zls = pkgs.zls_0_15;
      };
    });

    formatter = forAllSystems (_: pkgs: pkgs.alejandra);
  };
}
