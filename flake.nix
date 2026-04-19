{
  description = "CLI/TUI for Spotify";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    zig = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-flake.follows = "zig";
      };
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
      zigVersion = "zig_${(import ./nix/version.nix nixpkgs.lib).zigVersion}";
    in
    {
      packages = forAllSystems (
        system: pkgs: {
          default = self.packages.${system}.zpotify;
          zpotify = pkgs.callPackage ./nix/package.nix {
            zig = inputs.zig.packages.${system}.${zigVersion};
          };
        }
      );

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.callPackage ./nix/shell.nix {
            zig = inputs.zig.packages.${system}.${zigVersion};
            zls = inputs.zls.packages.${system}.default;
          };
        }
      );

      formatter = forAllSystems (_: pkgs: pkgs.nixfmt-tree);
    };
}
