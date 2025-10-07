{
  description = "Pytest flake using uv2nix";

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
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      nixpkgs,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      # Python sets grouped per system
      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) stdenv;

          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python312;
          };

          # An overlay of build fixups & test additions.
          pyprojectOverrides = final: prev: {

            # testing is the name of our example package
            testing = prev.testing.overrideAttrs (old: {

              passthru = old.passthru // {
                # Put all tests in the passthru.tests attribute set.
                # Nixpkgs also uses the passthru.tests mechanism for ofborg test discovery.
                #
                # For usage with Flakes we will refer to the passthru.tests attributes to construct the flake checks attribute set.
                tests =
                  let
                    # Construct a virtual environment with only the test dependency-group enabled for testing.
                    virtualenv = final.mkVirtualEnv "testing-pytest-env" {
                      testing = [ "test" ];
                    };

                  in
                  (old.tests or { })
                  // {
                    pytest = stdenv.mkDerivation {
                      name = "${final.testing.name}-pytest";
                      inherit (final.testing) src;
                      nativeBuildInputs = [
                        virtualenv
                      ];
                      dontConfigure = true;

                      # Because this package is running tests, and not actually building the main package
                      # the build phase is running the tests.
                      #
                      # In this particular example we also output a HTML coverage report, which is used as the build output.
                      buildPhase = ''
                        runHook preBuild
                        pytest --cov tests --cov-report html
                        runHook postBuild
                      '';

                      # Install the HTML coverage report into the build output.
                      #
                      # If you wanted to install multiple test output formats such as TAP outputs
                      # you could make this derivation a multiple-output derivation.
                      #
                      # See https://nixos.org/manual/nixpkgs/stable/#chap-multiple-output for more information on multiple outputs.
                      installPhase = ''
                        runHook preInstall
                        mv htmlcov $out
                        runHook postInstall
                      '';
                    };

                  };
              };
            });
          };

        in
        baseSet.overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        )
      );

    in
    {
      # Construct flake checks from Python set
      checks = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};
        in
        {
          inherit (pythonSet.testing.passthru.tests) pytest;
        }
      );
    };
}
