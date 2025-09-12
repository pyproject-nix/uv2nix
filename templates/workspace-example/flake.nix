{
  description = "Example flake demonstrating native UV workspace support in uv2nix";

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
      # Support multiple systems
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = lib.genAttrs systems;

    in
    {
      # Example 1: Create environments for specific workspace members
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          
          # Load the UV workspace with native member support
          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

          # Create package overlay from workspace
          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          # Create Python package set
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              (lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
              ]);
        in
        {
          # Environment with all workspace dependencies
          default = pythonSet.mkVirtualEnv "workspace-env" workspace.deps.default;

          # Example 3: Container images for specific workspace members (Linux only)
          docker = if lib.hasInfix "linux" system then
            {
              # Minimal container with workspace
              workspace = pkgs.dockerTools.buildImage {
                name = "myapp-workspace";
                tag = "latest";
                contents = [
                  (pythonSet.mkVirtualEnv "workspace-container" 
                    workspace.deps.default)
                ];
                config = {
                  Cmd = [ "python" "-m" "myapp.main" ];
                };
              };
            }
          else
            { };

          # Example 4: CI/CD jobs for specific members
          ci = {
            # Test job for web app
            test-webapp = pkgs.writeShellScriptBin "test-webapp" ''
              set -e
              echo "Testing webapp with dependencies: fastapi, shared, uvicorn"
              # Run webapp tests
            '';

            # Test job for API
            test-api = pkgs.writeShellScriptBin "test-api" ''
              set -e
              echo "Testing API with dependencies: httpx, pydantic, shared"
              # Run API tests
            '';

            # Lint job for shared library
            lint-shared = pkgs.writeShellScriptBin "lint-shared" ''
              set -e
              echo "Linting shared library with dependencies: pydantic, typing-extensions"
              # Run linting
            '';
          };

          # Example 5: Demonstrate the new API features
          examples = {
            # Show workspace members
            list-members = pkgs.writeShellScriptBin "list-members" ''
              echo "Workspace members:"
              echo "  - api"
              echo "  - myapp"
              echo "  - shared"
              echo "  - webapp"
            '';

            # Show member information
            show-member-info = pkgs.writeShellScriptBin "show-member-info" ''
              echo "Member information:"
              echo "  api:"
              echo "    Path: packages/api"
              echo "    Version: 0.1.0"
              echo "    Dependencies: httpx, pydantic, shared"
              echo "  webapp:"
              echo "    Path: packages/webapp"
              echo "    Version: 0.1.0"
              echo "    Dependencies: fastapi, shared, uvicorn"
              echo "  shared:"
              echo "    Path: packages/shared"
              echo "    Version: 0.1.0"
              echo "    Dependencies: pydantic, typing-extensions"
            '';

            # Show member dependencies
            show-member-deps = pkgs.writeShellScriptBin "show-member-deps" ''
              echo "Member dependencies:"
              echo "  api:"
              echo "    Default: httpx, pydantic, shared"
              echo "    Optionals: "
              echo "    Groups: "
              echo "  webapp:"
              echo "    Default: fastapi, shared, uvicorn"
              echo "    Optionals: "
              echo "    Groups: "
              echo "  shared:"
              echo "    Default: pydantic, typing-extensions"
              echo "    Optionals: "
              echo "    Groups: "
            '';
          };
        }
      );

      # Example 2: Development shells for different parts of the workspace
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          
          # Load the UV workspace with native member support
          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

          # Create package overlay from workspace
          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          # Create Python package set
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              (lib.composeManyExtensions [
                pyproject-build-systems.overlays.default
                overlay
              ]);
        in
        {
          # Shell with all workspace dependencies
          default = pkgs.mkShell {
            packages = [
              (pythonSet.mkVirtualEnv "workspace-dev" 
                workspace.deps.all)
              pkgs.uv
            ];
            env = {
              # Force uv to use nixpkgs Python interpreter
              UV_PYTHON = pkgs.python312.interpreter;
              # Prevent uv from downloading managed Python's
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              # Undo dependency propagation by nixpkgs.
              unset PYTHONPATH
            '';
          };
        }
      );

    };
}
