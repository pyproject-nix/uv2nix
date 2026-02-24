# Source filtering

Nix has functionality to apply filtering to local sources when copying to the store.
This allows users to tune how often a package is rebuilt by controlling what sources affect the Nix store path hashing.

## Editable packages

Source selection/filtering is extra important for editable packages, which should ideally only be rebuilt when project metadata changes.

Most Python build backends only require enough sources to discover what importable Python packages to provide for an editable build to succeed:
```nix
let
  # [...] workspace, overlay etc

  editableOverlay = workspace.mkEditablePyprojectOverlay {
    root = "$REPO_ROOT";
  };

  pyprojectOverrides = final: prev: {
    app = prev.app.overrideAttrs (old: {
      src = lib.fileset.toSource rec {
        root = ./.;
        fileset = lib.fileset.unions [
          (root + "/pyproject.toml")
          (root + "/app/__init__.py")
        ];
      };
    });
  };

  pythonSet = pythonBase.overrideScope (
    lib.composeManyExtensions [
      # ...
      pyproject-build-systems.overlays.wheel
      overlay
      editableOverlay
      pyprojectOverrides
    ]
  );

  virtualenv = pythonSet.mkVirtualEnv "app-dev-env" workspace.deps.all;
in
  pkgs.mkShell {
    packages = [
      virtualenv
      pkgs.uv
    ];

    env = {
      UV_NO_SYNC = "1";
      UV_PYTHON = pythonSet.python.interpreter;
      UV_PYTHON_DOWNLOADS = "never";
    };

    shellHook = ''
      unset PYTHONPATH
      export REPO_ROOT=$(git rev-parse --show-toplevel)
    '';
  };
}
```
This example uses the [fileset](https://nix.dev/tutorials/working-with-local-files.html) API to explicitly select sources.

Another way to reduce the amount of rebuilds even further is to construct dummy sources:
```nix
  pyprojectOverrides = final: prev: {
    app = prev.app.overrideAttrs(old: {
      src = pkgs.runCommand "app-src" {} ''
        mkdir $out
        cp ${./pyproject.toml} $out/pyproject.toml
        mkdir $out/app
        touch $out/app/__init__.py
      '';
    });
  };
```

## External resources

- [builtins.filterSource](https://nix.dev/manual/nix/latest/language/builtins#builtins-filterSource)
- [lib.cleanSource](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.sources.cleanSource)
- [Working with local files (fileset)](https://nix.dev/tutorials/working-with-local-files.html)
