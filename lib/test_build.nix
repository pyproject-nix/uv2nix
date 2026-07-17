{
  lib,
  pyproject-nix,
  pkgs,
  lock1,
  workspace,
  build,
  ...
}:

let
  inherit (lib) mapAttrs findFirst importTOML;

  projectDirs = {
    workspace = ./fixtures/workspace;
    kitchenSinkA = ./fixtures/kitchen-sink/a;
    kitchenSinkCEditable = ./fixtures/kitchen-sink/c-editable;
    kitchenSinkB = ./fixtures/kitchen-sink/b;
    withExtra = ./fixtures/with-extra;
    trivial = ./fixtures/trivial;
    multiChoicePackage = ./fixtures/multi-choice-package;
    workspaceFlat = ./fixtures/workspace-flat;
    optionalDeps = ./fixtures/optional-deps;
    noDeps = ./fixtures/no-deps;
    withToolUvDevDeps = ./fixtures/with-tool-uv-devdeps;
    withResolverOptions = ./fixtures/with-resolver-options;
    withSupportedEnvironments = ./fixtures/with-supported-environments;
    multiPythons = ./fixtures/multi-pythons;
    no-build-no-binary-packages = ./fixtures/no-build-no-binary-packages;
    no-build = ./fixtures/no-build;
    no-binary = ./fixtures/no-binary;
    no-binary-no-build = ./fixtures/no-binary-no-build;
  };

  projects = mapAttrs (
    _: dir: pyproject-nix.lib.project.loadUVPyproject { projectRoot = dir; }
  ) projectDirs;

  findFirstPkg = name: findFirst (package: package.name == name) (throw "Not found: ${name}");

  locks = mapAttrs (_: dir: importTOML (dir + "/uv.lock")) projectDirs;

in
{

  remote =
    let

      # Return a callPackage'd package.
      mkPackageTest =
        {
          projectName,
          workspaceRoot ? projectDirs.${projectName},
          python ? pkgs.python312,
          sourcePreference,
        }:
        let
          buildRemotePackage = build.remote {
            inherit workspaceRoot;
            config = workspace.loadConfig projects.${projectName}.pyproject [
              projects.${projectName}.pyproject
            ];
            defaultSourcePreference = sourcePreference;
            environ = null;
          };
        in
        depName:
        let
          package = lock1.parsePackage { } (findFirstPkg depName locks.${projectName}.package);
        in
        pkgs.callPackage (buildRemotePackage package) {
          pyprojectHook = null;
          pyprojectWheelHook = null;
          inherit python sourcePreference;
          resolveBuildSystem = null;
        };

    in
    {
      testNoBinaryPackagesPrefWheel = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "wheel";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };

      testNoBinaryPackagesPrefSdist = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "sdist";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };

      testNoBuildPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-build";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2-py2.py3-none-any.whl";
      };

      testNoBuildPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-build";
                sourcePreference = "sdist";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2-py2.py3-none-any.whl";
      };

      testNoBinaryPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2.tar.gz";
      };

      testNoBinaryPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary";
                sourcePreference = "sdist";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2.tar.gz";
      };

      testNoBuildNoBinaryPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary-no-build";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "Package source for 'arpeggio' was derived as wheel, but tool.uv.no-binary is set to true";
      };

      testNoBuildNoBinaryPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary-no-build";
                sourcePreference = "sdist";
              })
              "arpeggio"
            ).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "Package source for 'arpeggio' was derived as wheel, but tool.uv.no-binary is set to true";
      };

      # Regression test: when tool.uv.no-build is set but no compatible wheel exists,
      # the source is derived as an sdist and the no-build assertion must fire.
      # Previously the assertion checked for format == "sdist" (a value never assigned)
      # so the sdist build would silently proceed.
      testNoBuildSdistFallback = {
        expr =
          let
            buildRemotePackage = build.remote {
              workspaceRoot = projectDirs.no-build;
              config = workspace.loadConfig projects.no-build.pyproject [ projects.no-build.pyproject ];
              defaultSourcePreference = "wheel";
              environ = null;
            };
            package = (lock1.parsePackage { } (findFirstPkg "arpeggio" locks.no-build.package)) // {
              wheels = [ ];
            };
          in
          baseNameOf
            (pkgs.callPackage (buildRemotePackage package) {
              pyprojectHook = null;
              pyprojectWheelHook = null;
              python = pkgs.python312;
              sourcePreference = "wheel";
              resolveBuildSystem = null;
            }).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "Package source for 'arpeggio' was derived as sdist, but tool.uv.no-build is set to true";
      };

      # Regression test: an sdist served from a local (path-based) registry has
      # `sdist.path` rather than `sdist.url`. Previously this fell into the
      # `fetchurl` branch and failed with `attribute 'url' missing`.
      testLocalIndexSdist = {
        expr =
          let
            projectDir = ./fixtures/local-index-sdist;
            project = pyproject-nix.lib.project.loadUVPyproject { projectRoot = projectDir; };
            buildRemotePackage = build.remote {
              workspaceRoot = projectDir;
              config = workspace.loadConfig project.pyproject [ project.pyproject ];
              defaultSourcePreference = "sdist";
              environ = null;
            };
            package = lock1.parsePackage { } (
              findFirstPkg "attrs" (importTOML (projectDir + "/uv.lock")).package
            );
          in
          baseNameOf (
            toString
              (pkgs.callPackage (buildRemotePackage package) {
                pyprojectHook = null;
                pyprojectWheelHook = null;
                python = pkgs.python312;
                sourcePreference = "sdist";
                resolveBuildSystem = null;
              }).src
          );
        expected = "attrs-23.1.0.tar.gz";
      };

      # Regression test: when a direct-URL wheel isn't found among the package's
      # wheels, the diagnostic should say so rather than fail with
      # "cannot coerce a list to a string".
      testWheelURLNotFound = {
        expr =
          let
            buildRemotePackage = build.remote {
              workspaceRoot = projectDirs.trivial;
              config = workspace.loadConfig projects.trivial.pyproject [ projects.trivial.pyproject ];
              defaultSourcePreference = "wheel";
              environ = null;
            };
            package = (lock1.parsePackage { } (findFirstPkg "arpeggio" locks.trivial.package)) // {
              source = {
                url = "https://example.org/nonexistent.whl";
              };
              sdist = { };
            };
          in
          (pkgs.callPackage (buildRemotePackage package) {
            pyprojectHook = null;
            pyprojectWheelHook = null;
            python = pkgs.python312;
            sourcePreference = "wheel";
            resolveBuildSystem = null;
          }).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "not found in list of wheels";
      };
    };

}
