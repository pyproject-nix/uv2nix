args@{
  lib,
  self,
  package-name,
  pythonSets,
  nixpkgs,
  ...
}:
lib.flake.forAllSystems (
  system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    pythonSet = pythonSets.${system};
    folders = lib.flake.getSubdirs ./.;
    folderAttrs = (
      name: {
        name = name;
        value = import ./${name} (
          args
          // {
            inherit pkgs system pythonSet;
          }
        ); # You can replace this with any value
      }
    );
  in
  builtins.listToAttrs (map folderAttrs folders)
  // {
    default = self.devShells.${system}.${package-name};
  }
)
