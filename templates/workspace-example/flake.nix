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

      # Load the UV workspace with native member support
      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      # Create package overlay from workspace
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      # Create Python package set
      pythonSet =
        (nixpkgs.callPackage pyproject-nix.build.packages {
          python = nixpkgs.python312;
        }).overrideScope
          overlay;

    in
    {
      # Example 1: Create environments for specific workspace members
      packages = {
        # Environment with only the web app dependencies
        webapp-env = pythonSet.mkVirtualEnv "webapp" 
          workspace.deps."webapp".default;

        # Environment with only the API library dependencies  
        api-env = pythonSet.mkVirtualEnv "api"
          workspace.deps."api".default;

        # Environment with only the shared library dependencies
        shared-env = pythonSet.mkVirtualEnv "shared"
          workspace.deps."shared".default;

        # Environment with all workspace dependencies
        full-env = pythonSet.mkVirtualEnv "full"
          workspace.deps.all;
      };

      # Example 2: Development shells for different parts of the workspace
      devShells = {
        # Shell for web app development
        webapp = nixpkgs.mkShell {
          packages = [
            (pythonSet.mkVirtualEnv "webapp-dev" 
              workspace.deps."webapp".all)
            nixpkgs.nodejs
            nixpkgs.yarn
          ];
        };

        # Shell for API development
        api = nixpkgs.mkShell {
          packages = [
            (pythonSet.mkVirtualEnv "api-dev" 
              workspace.deps."api".all)
            nixpkgs.postgresql
            nixpkgs.redis
          ];
        };

        # Shell for shared library development
        shared = nixpkgs.mkShell {
          packages = [
            (pythonSet.mkVirtualEnv "shared-dev" 
              workspace.deps."shared".all)
          ];
        };

        # Shell with all workspace dependencies
        full = nixpkgs.mkShell {
          packages = [
            (pythonSet.mkVirtualEnv "full-dev" 
              workspace.deps.all)
          ];
        };
      };

      # Example 3: Container images for specific workspace members
      packages.docker = {
        # Minimal container with only web app
        webapp = nixpkgs.dockerTools.buildImage {
          name = "myapp-webapp";
          tag = "latest";
          contents = [
            (pythonSet.mkVirtualEnv "webapp-container" 
              workspace.deps."webapp".default)
          ];
          config = {
            Cmd = [ "python" "-m" "webapp.main" ];
          };
        };

        # API-only container
        api = nixpkgs.dockerTools.buildImage {
          name = "myapp-api";
          tag = "latest";
          contents = [
            (pythonSet.mkVirtualEnv "api-container" 
              workspace.deps."api".default)
          ];
          config = {
            Cmd = [ "python" "-m" "api.main" ];
          };
        };
      };

      # Example 4: CI/CD jobs for specific members
      packages.ci = {
        # Test job for web app
        test-webapp = nixpkgs.writeShellScriptBin "test-webapp" ''
          set -e
          echo "Testing webapp with dependencies: ${lib.concatStringsSep ", " workspace.deps."webapp".default}"
          # Run webapp tests
        '';

        # Test job for API
        test-api = nixpkgs.writeShellScriptBin "test-api" ''
          set -e
          echo "Testing API with dependencies: ${lib.concatStringsSep ", " workspace.deps."api".default}"
          # Run API tests
        '';

        # Lint job for shared library
        lint-shared = nixpkgs.writeShellScriptBin "lint-shared" ''
          set -e
          echo "Linting shared library with dependencies: ${lib.concatStringsSep ", " workspace.deps."shared".default}"
          # Run linting
        '';
      };

      # Example 5: Demonstrate the new API features
      packages.examples = {
        # Show workspace members
        list-members = nixpkgs.writeShellScriptBin "list-members" ''
          echo "Workspace members:"
          ${lib.concatMapStringsSep "\n" (member: "echo '  - ${member}'") workspace.members}
        '';

        # Show member information
        show-member-info = nixpkgs.writeShellScriptBin "show-member-info" ''
          echo "Member information:"
          ${lib.concatMapStringsSep "\n" (member: 
            let info = workspace.getMemberInfo member;
            in ''
              echo "  ${member}:"
              echo "    Path: ${info.path}"
              echo "    Version: ${info.version}"
              echo "    Description: ${info.description}"
              echo "    Dependencies: ${lib.concatStringsSep ", " info.dependencies.dependencies}"
            ''
          ) workspace.members}
        '';

        # Show member dependencies
        show-member-deps = nixpkgs.writeShellScriptBin "show-member-deps" ''
          echo "Member dependencies:"
          ${lib.concatMapStringsSep "\n" (member: 
            let deps = workspace.getMemberDeps member;
            in ''
              echo "  ${member}:"
              echo "    Default: ${lib.concatStringsSep ", " deps.default}"
              echo "    Optionals: ${lib.concatStringsSep ", " deps.optionals}"
              echo "    Groups: ${lib.concatStringsSep ", " deps.groups}"
            ''
          ) workspace.members}
        '';
      };
    };
}
