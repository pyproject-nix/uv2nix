{
  description = "Django application using uv2nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      pyproject-nix,
      pyproject-build-systems,
      uv2nix,

      ...
    }:
    let
      lib = nixpkgs.lib.extend (
        self: _: {
          flake = import ./nix/lib (
            {
              lib = self;
            }
            // inputs
          );
        }
      );
      package-name = "django-webapp";
      pythonSets = import ./pythonSets.nix ({ inherit lib; } // inputs);
      allArgs = inputs // {
        inherit lib package-name pythonSets;
      };

      nixDirs = lib.flake.getSubdirs ./nix;
      importFolder = (
        name: {
          name = name;
          value =

            import ./nix/${name} allArgs;
        }
      );
    in
    {
      asgiApp = "django_webapp.asgi:application";
      settingsModules = {
        prod = "django_webapp.settings";
      };
    }
    // builtins.listToAttrs (map importFolder nixDirs);
}
