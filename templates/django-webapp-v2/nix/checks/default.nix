{
  lib,
  self,
  package-name,
  ...
}:
lib.flake.forAllSystems (
  system:
  let
    mainPkg = self.packages.${system}.${package-name};
  in

  rec {
    inherit (mainPkg) tests;
    inherit (mainPkg.tests) mypy pytest nixos;
    default = pytest;
  }

)
