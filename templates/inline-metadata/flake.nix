{
  description = "Use PEP-723 inline metadata scripts with uv2nix";

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
    {
      self,
      nixpkgs,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      # Map over all nixpkgs supported systems to create the `packages` set
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      # Load all Python scripts from ./scripts directory
      scripts =
        lib.mapAttrs
          (
            name: _:
            uv2nix.lib.scripts.loadScript {
              script = ./scripts + "/${name}";
            }
          )
          (
            lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".py" name) (
              builtins.readDir ./scripts
            )
          );

      packages' = forAllSystems (
        system:
        let
          # Nixpkgs package set
          pkgs = nixpkgs.legacyPackages.${system};

          # Use Python 3.12
          python = pkgs.python312;

          # Use base package set from pyproject.nix builders
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            inherit python;
          };

          # Implement build fixups here.
          pyprojectOverrides = _final: _prev: {
          };

        in
        lib.mapAttrs (
          name: script:
          let
            # Create package overlay from workspace.
            overlay = script.mkOverlay {
              sourcePreference = "wheel";
            };

            # Construct package set
            pythonSet = baseSet.overrideScope (
              lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
                pyprojectOverrides
              ]
            );
          in
          # Write out an executable script with a shebang pointing to the scripts virtualenv
          pkgs.writeScript script.name (
            # Returns script as a string with inserted shebang
            script.renderScript {
              # Construct a virtual environment for script
              venv = script.mkVirtualEnv {
                inherit pythonSet;
              };
            }
          )
        ) scripts
      );

    in
    {
      # Drop .py suffix from scripts, making example.py runnable as example
      packages = forAllSystems (
        system:
        lib.mapAttrs' (name: drv: lib.nameValuePair (lib.removeSuffix ".py" name) drv) packages'.${system}
      );

      # Make each script runnable directly with `nix run`
      apps = forAllSystems (
        system:
        lib.mapAttrs (_name: script: {
          type = "app";
          program = "${script}";
        }) self.packages.${system}
      );

      # Use an impure devshell as we're managing many scripts and can't build a single cohesive environment.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python312;
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              pkgs.uv
            ];
            env =
              {
                UV_PYTHON_DOWNLOADS = "never";
                UV_PYTHON = python.interpreter;
              }
              // lib.optionalAttrs pkgs.stdenv.isLinux {
                LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
              };
            shellHook = ''
              unset PYTHONPATH
            '';
          };
        }
      );
    };
}
