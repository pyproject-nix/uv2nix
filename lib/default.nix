{ lib, pyproject-nix }:
let
  inherit (builtins) mapAttrs;
  inherit (lib) fix;
in
fix (
  self:
  mapAttrs (_: path: import path ({ inherit lib pyproject-nix; } // self)) {
    fetchers = ./fetchers.nix;
    lock1 = ./lock1.nix;
    workspace = ./workspace.nix;
    build = ./build.nix;
    overlays = ./overlays.nix;
    scripts = ./scripts.nix;
  }
)
