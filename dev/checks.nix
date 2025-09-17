{
  pkgs,
  uv2nix,
  lib,
  pyproject-nix,
}:
let
  inherit (pkgs) runCommand stdenv;
  inherit (lib)
    mapAttrs'
    nameValuePair
    ;

  buildSystems' = import ./build-systems.nix;
  buildSystems = lib.composeExtensions (_final: prev: {
    pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope buildSystems';
  }) buildSystems';

  buildSystemOverrides = import ./build-system-overrides.nix;
  patchingDeps = import ./patching-deps.nix;

  mkCheck' =
    sourcePreference:
    {
      root,
      interpreter ? pkgs.python312,
      spec ? { },
      check ? null,
      name ? throw "No name provided",
      environ ? { },
    }:
    let
      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };

      # Build Python environment based on builder implementation
      pythonEnv =
        let
          # Generate overlay
          overlay = ws.mkPyprojectOverlay (
            {
              inherit sourcePreference environ;
            }
            // lib.optionalAttrs (spec != { }) {
              dependencies = spec;
            }
          );

          # Construct package set
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = interpreter;
            }).overrideScope
              (
                lib.composeManyExtensions [
                  buildSystems
                  overlay
                  buildSystemOverrides
                  patchingDeps
                ]
              );

        in
        # Render venv
        pythonSet.pythonPkgsHostHost.mkVirtualEnv "test-venv" spec;

    in
    if check != null then
      runCommand "check-${name}-pref-${sourcePreference}"
        {
          nativeBuildInputs = [ pythonEnv ];
        }
        ''
          ${check}
          touch $out
        ''
    else
      pythonEnv;

  mkChecks =
    sourcePreference:
    let
      mkCheck = mkCheck' sourcePreference;
      # Returns true iff this fails to evaluate
      mkFail = args: ! (builtins.tryEval (mkCheck args)).success;
      nameSuffix = if sourcePreference == "wheel" then "" else "-pref-${sourcePreference}";

    in
    assert mkFail {
      root = ../lib/fixtures/dependency-group-conflicts;
      spec = {
        dependency-group-conflicts = [ "group-a" "group-b" ];
      };
    };
    mapAttrs' (name: v: nameValuePair "${name}${nameSuffix}" v) {
      trivial = mkCheck {
        root = ../lib/fixtures/trivial;
        spec = {
          trivial = [ ];
        };
      };

      kitchenSinkA = mkCheck {
        root = ../lib/fixtures/kitchen-sink/a;
        spec = {
          a = [ ];
        };
      };

      onlyWheels = mkCheck {
        root = ../lib/fixtures/only-wheels;
        spec = {
          hgtk = [ ];
        };
      };
    }
    // lib.optionalAttrs (sourcePreference != "wheel") {
      virtual = mkCheck {
        root = ../lib/fixtures/virtual;
        spec = {
          virtual = [ ];
        };
      };

      workspace = mkCheck {
        root = ../lib/fixtures/workspace;
        spec = {
          workspace = [ ];
          workspace-package = [ ];
        };
      };

      workspace-flat = mkCheck {
        root = ../lib/fixtures/workspace-flat;
        spec = {
          pkg-a = [ ];
          pkg-b = [ ];
        };
      };

      kitchenSinkA = mkCheck {
        root = ../lib/fixtures/kitchen-sink/a;
        spec = {
          a = [ ];
        };
      };

      noDeps = mkCheck {
        root = ../lib/fixtures/no-deps;
        spec = {
          no-deps = [ ];
        };
      };

      dependencyGroups = mkCheck {
        name = "dependency-groups";
        root = ../lib/fixtures/dependency-groups;
        spec = {
          dependency-groups = [ "group-a" ];
        };
        check = ''
          python -c 'import urllib3'
          python -c 'import arpeggio' && exit 1
        '';
      };

      dependencyGroupNoSelect = mkCheck {
        name = "dependency-groups-noselect";
        root = ../lib/fixtures/dependency-groups;
        spec = {
          dependency-groups = [ ];
        };
        check = ''
          python -c 'import urllib3' && exit 1
          python -c 'import arpeggio' && exit 1
        '';
      };

      dependencyGroupNone = mkCheck {
        name = "dependency-group-conflicts-noselect";
        root = ../lib/fixtures/dependency-group-conflicts;
        spec = {
          dependency-group-conflicts = [ ];
        };
        check = ''
          python -c 'import urllib3' && exit 1
          python -c 'import arpeggio' && exit 1
          python -c 'import tqdm' && exit 1
        '';
      };

      dependencyGroupConflictsA = mkCheck {
        name = "dependency-groups-a";
        root = ../lib/fixtures/dependency-group-conflicts;
        spec = {
          dependency-group-conflicts = [ "group-a" ];
        };
        check = ''
          python -c 'import urllib3'
          python -c 'import arpeggio' && exit 1
          python -c 'import tqdm' && exit 1
        '';
      };

      dependencyGroupConflictsB = mkCheck {
        name = "dependency-groups-b";
        root = ../lib/fixtures/dependency-group-conflicts;
        spec = {
          dependency-group-conflicts = [ "group-b" ];
        };
        check = ''
          python -c 'import urllib3' && exit 1
          python -c 'import arpeggio'
          python -c 'import tqdm' && exit 1
        '';
      };

      dependencyGroupConflictsBC = mkCheck {
        name = "dependency-groups-bc";
        root = ../lib/fixtures/dependency-group-conflicts;
        spec = {
          dependency-group-conflicts = [ "group-b" "group-c" ];
        };
        check = ''
          python -c 'import urllib3' && exit 1
          python -c 'import arpeggio'
          python -c 'import tqdm'
        '';
      };

      optionalDeps = mkCheck {
        root = ../lib/fixtures/optional-deps;
        spec = {
          optional-deps = [ ];
        };
      };

      patchedArpeggio = mkCheck {
        name = "patched-arpeggio";
        root = ../lib/fixtures/workspace;
        spec = {
          arpeggio = [ ];
        };
        check = ''
          python -c 'import arpeggio.patched'
        '';
      };

      withExtra = mkCheck {
        name = "with-extra";
        root = ../lib/fixtures/with-extra;
        spec = {
          with-extra = [ ];
        };
        # Check that socks extra is available
        check = ''
          python -c "import socks"
        '';
      };

      testMultiChoicePackageNoMarker = mkCheck {
        name = "multi-choice-no-marker";
        root = ../lib/fixtures/multi-choice-package;
        spec = {
          multi-choice-package = [ ];
        };
        # Check that arpeggio _isn't_ available
        check = ''
          python -c "import arpeggio" && exit 1
        '';
      };

      testMultiChoicePackageWithMarker = mkCheck {
        name = "multi-choice-with-marker";
        root = ../lib/fixtures/multi-choice-package;
        spec = {
          multi-choice-package = [ ];
        };

        # Check that arpeggio _is_ available
        check = ''
          python -c "import arpeggio"
        '';
        environ = {
          platform_release = "5.10.65";
        };
      };

      # Nixpkgs buildPythonPackage explodes when bootstrap deps are overriden
      bootstrapProjectDep = mkCheck {
        root = ../lib/fixtures/bootstrap-project-dep;
        spec = {
          packaging = [ ];
        };
      };

      overridenRegistry = mkCheck {
        root = ../lib/fixtures/overriden-registry;
        spec = {
          overriden-registry = [ ];
        };
      };

      dynamicDeps = mkCheck {
        name = "dynamic-deps";
        root = ../lib/fixtures/dynamic-dependencies;
        spec = {
          dynamic-dependencies = [ ];
        };
        check = ''
          python -c 'import tqdm'
        '';
      };

      conflictsA = mkCheck {
        name = "conflicts-group-a";
        root = ../lib/fixtures/conflicts;
        spec = {
          conflicts = [ "extra-a" ];
        };
        check = ''
          python -c 'import arpeggio'
        '';
      };

      conflictsB = mkCheck {
        name = "conflicts-group-b";
        root = ../lib/fixtures/conflicts;
        spec = {
          conflicts = [ "extra-b" ];
        };
        check = ''
          python -c 'import arpeggio'
        '';
      };

      dynamicVersion = mkCheck {
        name = "dynamic-version";
        root = ../lib/fixtures/dynamic-version;
        spec = {
          dynamic-version = [ ];
        };
      };

      gitSubdirectory = mkCheck {
        name = "git-subdirectory";
        root = ../lib/fixtures/git-subdirectory;
        spec = {
          git-subdirectory = [ ];
        };
      };

      editable-workspace =
        let
          workspaceRoot = ../lib/fixtures/workspace;
          ws = uv2nix.workspace.loadWorkspace { inherit workspaceRoot; };

          interpreter = pkgs.python312;

          # Generate overlays
          overlay = ws.mkPyprojectOverlay {
            inherit sourcePreference;
            environ = { };
          };
          editableOverlay = ws.mkEditablePyprojectOverlay {
            root = "$NIX_BUILD_TOP";
          };

          # Base package set
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = interpreter;
          };

          # Override package set with our overlays
          pythonSet = baseSet.overrideScope (
            lib.composeManyExtensions [
              buildSystems
              overlay
              buildSystemOverrides
              patchingDeps
              editableOverlay
              (final: prev: {
                workspace = prev.workspace.overrideAttrs (old: {
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });

                workspace-package = prev.workspace-package.overrideAttrs (old: {
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });
              })
            ]
          );

          pythonEnv = pythonSet.pythonPkgsHostHost.mkVirtualEnv "editable-venv" {
            workspace = [ ];
          };

        in
        pkgs.runCommand "editable-workspace-test"
          {
            nativeBuildInputs = [ pythonEnv ];
          }
          ''
            cp -r ${workspaceRoot}/* .

            chmod +w .*
            test "$(python -c 'import workspace_package; print(workspace_package.hello())')" = "Hello from workspace-package!"
            substituteInPlace ./packages/workspace-package/src/workspace_package/__init__.py --replace-fail workspace-package mutable-package
            test "$(python -c 'import workspace_package; print(workspace_package.hello())')" = "Hello from mutable-package!"
            touch $out
          '';

      editable-parent-dir =
        let
          workspaceRoot = ../lib/fixtures/kitchen-sink/a;
          cEditableRoot = ../lib/fixtures/kitchen-sink/c-editable;
          ws = uv2nix.workspace.loadWorkspace { inherit workspaceRoot; };

          interpreter = pkgs.python312;

          # Generate overlays
          overlay = ws.mkPyprojectOverlay {
            inherit sourcePreference;
            environ = { };
          };
          editableOverlay = ws.mkEditablePyprojectOverlay {
            root = "$NIX_BUILD_TOP/a";
            members = [
              "a"
              "c-editable"
            ];
          };

          # Base package set
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = interpreter;
          };

          # Override package set with our overlays
          pythonSet = baseSet.overrideScope (
            lib.composeManyExtensions [
              buildSystems
              overlay
              buildSystemOverrides
              patchingDeps
              editableOverlay
              (final: prev: {
                a = prev.a.overrideAttrs (old: {
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });

                c-editable = prev.c-editable.overrideAttrs (old: {
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });
              })
            ]
          );

          pythonEnv = pythonSet.pythonPkgsHostHost.mkVirtualEnv "editable-venv" {
            a = [ ];
          };

        in
        pkgs.runCommand "editable-parent-dir-test"
          {
            nativeBuildInputs = [
              pkgs.findutils
              pythonEnv
            ];
          }
          ''
            cp -r ${workspaceRoot} a
            cp -r ${cEditableRoot} c-editable
            chmod -R +w a c-editable

            test "$(python -c 'import c_editable; print(c_editable.hello())')" = "Hello from c-editable!"
            substituteInPlace ./c-editable/src/c_editable/__init__.py --replace-fail c-editable mutable-package
            test "$(python -c 'import c_editable; print(c_editable.hello())')" = "Hello from mutable-package!"
            touch $out
          '';

      workspace-with-legacy = mkCheck {
        name = "conflicts-group-b";
        root = ../lib/fixtures/workspace-with-legacy;
        spec = {
          workspace-with-legacy = [ ];
        };
        check = ''
          test "$(python -c 'import workspace_with_legacy')" == "legacy-package"
        '';
      };
    };
in
# Generate test matrix:
# builder impl  -> sourcePreference
mkChecks "wheel"
// mkChecks "sdist"
// (lib.optionalAttrs (!stdenv.isDarwin) {

  cross =
    let
      root = ../lib/fixtures/kitchen-sink/a;

      pkgsCross = pkgs.pkgsCross.aarch64-multiplatform;

      ws = uv2nix.workspace.loadWorkspace { workspaceRoot = root; };

      overlay = ws.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      interpreter = pkgsCross.python3;

      pythonSet =
        (pkgsCross.callPackage pyproject-nix.build.packages {
          python = interpreter;
        }).overrideScope
          (
            lib.composeManyExtensions [
              buildSystems
              overlay
              buildSystemOverrides
              patchingDeps
            ]
          );
    in
    pythonSet.charset-normalizer;

})
// {
  scripts =
    let
      script = uv2nix.scripts.loadScript { script = ../lib/fixtures/inline-metadata/trivial.py; };

      overlay = script.mkOverlay {
        sourcePreference = "wheel";
      };

      python = pkgs.python312;

      baseSet = pkgs.callPackage pyproject-nix.build.packages {
        inherit python;
      };

      pythonSet = baseSet.overrideScope (
        lib.composeManyExtensions [
          buildSystems
          overlay
          buildSystemOverrides
          patchingDeps
        ]
      );

      pythonEnv = script.mkVirtualEnv {
        inherit pythonSet;
      };

      script' = pkgs.writeScript script.name (script.renderScript { venv = pythonEnv; });

    in
    pkgs.runCommand "script-test" { } ''
      ${script'} > /dev/null
      touch $out
    '';

}
