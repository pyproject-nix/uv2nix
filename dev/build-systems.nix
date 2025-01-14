# Build system packages for testing
# TODO: This file is a temporary arrangement to avoid Flake dependencies.
# The solution to removing this file is to stop using flakes for CI so we can depend on https://github.com/pyproject-nix/build-system-pkgs

final: _prev:
let
  pkgs = final.callPackage ({ pkgs }: pkgs) { };
  inherit (pkgs) python3Packages;
in
builtins.mapAttrs (_n: v: final.callPackage v { }) {

  flit-core =
    { stdenv, pyprojectHook }:
    stdenv.mkDerivation {
      inherit (python3Packages.flit-core)
        pname
        version
        src
        meta
        patches
        ;
      postPatch = python3Packages.flit-core.postPatch or null;
      sourceRoot = python3Packages.flit-core.sourceRoot or null;
      nativeBuildInputs = [
        pyprojectHook
      ];
    };

  cmake =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.cmake)
        pname
        version
        src
        meta
        postUnpack
        setupHooks
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  scikit-build-core =
    {
      stdenv,
      lib,
      python,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.scikit-build-core)
        pname
        version
        src
        meta
        patches
        ;

      passthru.dependencies =
        {
          packaging = [ ];
          pathspec = [ ];
        }
        // lib.optionalAttrs (python.pythonOlder "3.11") {
          exceptiongroup = [ ];
          tomli = [ ];
        }
        // lib.optionalAttrs (python.pythonOlder "3.9") {
          importlib-resources = [ ];
          typing-extensions = [ ];
        }
        // lib.optionalAttrs (python.pythonOlder "3.8") {
          importlib-metadata = [ ];
        };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          hatchling = [ ];
          hatch-vcs = [ ];
        };
    };

  ninja =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.ninja)
        pname
        version
        src
        meta
        postUnpack
        setupHook
        preBuild
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  cython =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
      pkg-config,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.cython)
        pname
        version
        src
        meta
        setupHook
        ;

      nativeBuildInputs =
        [
          pyprojectHook
          pkg-config
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
        };
    };

  pytest-runner =
    {
      stdenv,
      fetchurl,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      pname = "pytest-runner";
      version = "6.0.1";

      src = fetchurl {
        url = "https://files.pythonhosted.org/packages/d7/7d/60976d532519c3a0b41e06a59ad60949e2be1af937cf02738fec91bfd808/pytest-runner-6.0.1.tar.gz";
        hash = "sha256-cNRzlYWnAI83v0kzwBP9sye4h4paafy7MxbIiILw9Js=";
      };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
          setuptools-scm = [ ];
        };
    };

  hatchling =
    {
      stdenv,
      lib,
      python,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation (finalAttrs: {
      inherit (python3Packages.hatchling)
        pname
        version
        src
        meta
        ;

      passthru.dependencies =
        {
          packaging = [ ];
          pathspec = [ ];
          pluggy = [ ];
          trove-classifiers = [ ];
        }
        // lib.optionalAttrs (python.pythonOlder "3.11") {
          tomli = [ ];
        };

      nativeBuildInputs = [
        pyprojectHook
      ] ++ resolveBuildSystem finalAttrs.passthru.dependencies;
    });

  pluggy =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.pluggy)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools-scm = [ ];
        };
    };

  trove-classifiers =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.trove-classifiers)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
          calver = [ ];
        };
    };

  build =
    {
      stdenv,
      lib,
      python,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.build)
        pname
        version
        src
        meta
        ;

      passthru.dependencies =
        {
          packaging = [ ];
          pyproject-hooks = [ ];

        }
        // lib.optionalAttrs (python.pythonOlder "3.11") {
          tomli = [ ];
        };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  pyproject-hooks =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.pyproject-hooks)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  packaging =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.packaging)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  setuptools-scm =
    {
      stdenv,
      lib,
      python,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.setuptools-scm)
        pname
        version
        src
        meta
        setupHook
        ;

      passthru = {
        dependencies =
          {
            packaging = [ ];
            setuptools = [ ];
          }
          // lib.optionalAttrs (python.pythonOlder "3.11") {
            tomli = [ ];
          }
          // lib.optionalAttrs (python.pythonOlder "3.10") {
            typing-extensions = [ ];
          };

        optional-dependencies = {
          toml = {
            tomli = [ ];
          };
          rich = {
            rich = [ ];
          };
        };
      };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem (
          {
            setuptools = [ ];
          }
          // lib.optionalAttrs (python.pythonOlder "3.11") {
            tomli = [ ];
          }
        );
    };

  setuptools =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.setuptools)
        pname
        version
        src
        meta
        patches
        preBuild # Skips windows files
        ;

      passthru.dependencies.wheel = [ ];

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  tomli-w =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.tomli-w)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  wheel =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.wheel)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  calver =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.calver)
        pname
        version
        src
        meta
        postPatch
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
        };
    };

  hatch-fancy-pypi-readme =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.hatch-fancy-pypi-readme)
        pname
        version
        src
        meta
        ;

      passthru.dependencies = {
        hatchling = [ ];
      };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          hatchling = [ ];
        };
    };

  hatch-vcs =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation (_finalAttrs: {
      inherit (python3Packages.hatch-vcs)
        pname
        version
        src
        meta
        ;

      passthru.dependencies = {
        hatchling = [ ];
        setuptools-scm = [ ];
      };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          hatchling = [ ];
        };
    });

  hatch-requirements-txt =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation (_finalAttrs: {
      inherit (python3Packages.hatch-requirements-txt)
        pname
        version
        src
        meta
        ;

      passthru.dependencies = {
        hatchling = [ ];
        packaging = [ ];
      };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          hatchling = [ ];
        };
    });

  setuptools-rust =
    {
      stdenv,
      lib,
      python,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.setuptools-rust)
        pname
        version
        src
        meta
        ;

      passthru.dependencies =
        {
          semantic-version = [ ];
          setuptools = [ ];
          typing-extensions = [ ];
        }
        // lib.optionalAttrs (python.pythonOlder "3.11") {
          tomli = [ ];
        };

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
          setuptools-scm = [ ];
        };
    };

  semantic-version =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.semantic-version)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
        };
    };

  typing-extensions =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.typing-extensions)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  pathspec =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.pathspec)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

  libcst =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
      rustPlatform,
      cargo,
      rustc,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.libcst)
        name
        pname
        src
        version
        cargoDeps
        cargoRoot
        ;
      passthru.dependencies = {
        pyyaml = [ ];
      };
      nativeBuildInputs =
        [
          pyprojectHook
          rustPlatform.cargoSetupHook
          cargo
          rustc
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
          setuptools-rust = [ ];
        };
    };

  pyyaml =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.pyyaml)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          setuptools = [ ];
        };
    };

  editables =
    {
      stdenv,
      python3Packages,
      pyprojectHook,
      resolveBuildSystem,
    }:
    stdenv.mkDerivation {
      inherit (python3Packages.editables)
        pname
        version
        src
        meta
        ;

      nativeBuildInputs =
        [
          pyprojectHook
        ]
        ++ resolveBuildSystem {
          flit-core = [ ];
        };
    };

}
