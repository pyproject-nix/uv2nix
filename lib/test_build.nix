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

      mkGitPackage =
        {
          source,
          config ? { },
        }:
        let
          buildRemotePackage =
            build.remote
              {
                workspaceRoot = ./.;
                config = {
                  compile-bytecode = true;
                  no-binary = false;
                  no-build = false;
                  no-binary-package = [ ];
                  no-build-package = [ ];
                  extra-build-dependencies = { };
                }
                // config;
                defaultSourcePreference = "sdist";
                environ = null;
              }
              {
                name = "git-package";
                version = "1.0.0";
                inherit source;
                dependencies = [ ];
                optional-dependencies = { };
                dev-dependencies = { };
                sdist = { };
                wheels = [ ];
              };
        in
        pkgs.callPackage buildRemotePackage {
          pyprojectHook = null;
          pyprojectWheelHook = null;
          python = pkgs.python312;
          resolveBuildSystem = null;
          fetchGit = args: {
            fetcher = "fetchGit";
            inherit args;
            outPath = "/fetchGit";
          };
          fetchTree = args: {
            fetcher = "fetchTree";
            inherit args;
            outPath = "/fetchTree";
          };
        };

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
        expectedError.msg = "Package source for 'arpeggio' was derived as sdist, in tool.uv.no-binary is set to true";
      };

      testNoBuildNoBinaryPrefSdist = {
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
        expectedError.msg = "Package source for 'arpeggio' was derived as sdist, in tool.uv.no-binary is set to true";
      };

      testGitSourceDefaultsToFetchGit = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://github.com/pypa/pip.git?tag=20.3.1#f94a429e17b450ac2d3432f46492416ac2cf58ad";
              };
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) url;
            inherit (drv.src.args) ref;
            inherit (drv.src.args) rev;
          };
        expected = {
          fetcher = "fetchGit";
          url = "https://github.com/pypa/pip.git";
          ref = "refs/tags/20.3.1";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };

      testGitHubSourceUsesFetchTreeInAutoMode = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://github.com/pypa/pip.git?tag=20.3.1#f94a429e17b450ac2d3432f46492416ac2cf58ad";
              };
              config.git-fetcher = "auto";
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) type;
            inherit (drv.src.args) owner;
            inherit (drv.src.args) repo;
            inherit (drv.src.args) rev;
          };
        expected = {
          fetcher = "fetchTree";
          type = "github";
          owner = "pypa";
          repo = "pip";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };

      testGitLabCustomHostUsesFetchTreeInAutoMode = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://gitlab.example.com/company/platform/internal-package.git#0123456789abcdef0123456789abcdef01234567";
              };
              config = {
                git-fetcher = "auto";
                git-forge-hosts."gitlab.example.com" = "gitlab";
              };
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) type;
            inherit (drv.src.args) owner;
            inherit (drv.src.args) repo;
            inherit (drv.src.args) host;
          };
        expected = {
          fetcher = "fetchTree";
          type = "gitlab";
          owner = "company%2Fplatform";
          repo = "internal-package";
          host = "gitlab.example.com";
        };
      };

      testCustomHostConfigPreservesBuiltInHosts = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://github.com/pypa/pip.git?tag=20.3.1#f94a429e17b450ac2d3432f46492416ac2cf58ad";
              };
              config = {
                git-fetcher = "auto";
                git-forge-hosts."gitlab.example.com" = "gitlab";
              };
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) type;
            inherit (drv.src.args) owner;
            inherit (drv.src.args) repo;
            inherit (drv.src.args) rev;
          };
        expected = {
          fetcher = "fetchTree";
          type = "github";
          owner = "pypa";
          repo = "pip";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };

      testForceGitOverrideWinsInAutoMode = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://github.com/pypa/pip.git?tag=20.3.1#f94a429e17b450ac2d3432f46492416ac2cf58ad";
              };
              config = {
                git-fetcher = "auto";
                git-fetcher-force-git = [ "github.com/pypa/pip" ];
              };
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) url;
            inherit (drv.src.args) ref;
            inherit (drv.src.args) rev;
          };
        expected = {
          fetcher = "fetchGit";
          url = "https://github.com/pypa/pip.git";
          ref = "refs/tags/20.3.1";
          rev = "f94a429e17b450ac2d3432f46492416ac2cf58ad";
        };
      };

      testUnknownGitHostFallsBackToFetchGit = {
        expr =
          let
            drv = mkGitPackage {
              source = {
                git = "https://git.example.com/company/internal-package.git#0123456789abcdef0123456789abcdef01234567";
              };
            };
          in
          {
            inherit (drv.src) fetcher;
            inherit (drv.src.args) url;
            inherit (drv.src.args) rev;
          };
        expected = {
          fetcher = "fetchGit";
          url = "https://git.example.com/company/internal-package.git";
          rev = "0123456789abcdef0123456789abcdef01234567";
        };
      };
    };

}
