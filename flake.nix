{
  description = "CLI/TUI for Spotify";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
  in {
    packages = forAllSystems (system: pkgs: {
      default = self.packages.${system}.zpotify;
      zpotify = pkgs.callPackage ./nix/package.nix {
        zig = pkgs.zig_0_15;
      };
    });

    devShells = forAllSystems (system: pkgs: {
      default = pkgs.callPackage ./nix/shell.nix {
        zig = pkgs.zig_0_15;
        zls = pkgs.zls_0_15;
      };
    });

    formatter = forAllSystems (_: pkgs: pkgs.alejandra);
  };
}
