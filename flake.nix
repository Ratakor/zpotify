{
  description = "CLI/TUI for Spotify";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    zig = {
      url = "github:silversquirl/zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      self,
      zig,
    }:
    let
      inherit (import ./nix/version.nix nixpkgs.lib) zigVersion;
      forAllSystems =
        f:
        builtins.mapAttrs (
          system: pkgs: f pkgs zig.packages.${system}."zig_${zigVersion}"
        ) nixpkgs.legacyPackages;
    in
    {
      packages = forAllSystems (
        pkgs: zig: {
          default = pkgs.callPackage ./nix/package.nix {
            inherit zig;
          };
        }
      );

      devShells = forAllSystems (
        pkgs: zig: {
          default = pkgs.callPackage ./nix/shell.nix {
            inherit zig;
            inherit (zig) zls;
          };
        }
      );

      formatter = forAllSystems (pkgs: zig: pkgs.nixfmt-tree);
    };
}
