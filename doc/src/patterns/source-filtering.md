# Source filtering

Nix has functionality to apply filtering to local sources when copying to the store.
This allows users to tune how often a package is rebuilt by controlling what sources affect the Nix store path hashing.

## Filtering the workspace root

While it's technically possible to filter sources at the workspace root level like:
```
workspace = uv2nix.lib.workspace.loadWorkspace {
  workspaceRoot = builtins.filterSource (_: _: true) ./.;
};
```
it's strongly recommended to avoid this pattern.

`uv2nix` reads from the workspace root at evaluation time, meaning that filtering sources on the workspace root level results in [import-from-derivation](https://nix.dev/manual/nix/latest/language/import-from-derivation).
It will also cause issues with editable packages.

## Source filtering packages

The correct way to filter sources with `uv2nix` is on the individual Python package level:

```nix
app = prev.app.overrideAttrs (old: {
  src = builtins.filterSource (_: _: true) old.src;
})
```

Source filtering is applied on the per-package level by applying an overlay:
```nix
let
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  editableOverlay = workspace.mkEditablePyprojectOverlay {
    root = "$REPO_ROOT";
  };

  pyprojectOverrides = final: prev: {
    app = prev.app.overrideAttrs (old: {
      src = builtins.filterSource (_: _: true) old.src;
    });
  };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages {
    inherit python;
  }).overrideScope
    (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.wheel
        overlay
        pyprojectOverrides
      ]
    );
in
  ...
```

## Editable packages

Source selection/filtering is extra important for editable packages, which should ideally only be rebuilt when project metadata changes.

Most Python build backends only require enough sources to discover what importable Python packages to provide for an editable build to succeed:
```nix
app = prev.app.overrideAttrs (old: {
  src = lib.fileset.toSource rec {
    root = ./.;
    fileset = lib.fileset.unions [
      (root + "/pyproject.toml")
      (root + "/app/__init__.py")
    ];
  };
});
```
This example uses the [fileset](https://nix.dev/tutorials/working-with-local-files.html) API to explicitly select sources.

Another way to reduce the amount of rebuilds even further is to construct dummy sources:
```nix
app = prev.app.overrideAttrs(old: {
  src = pkgs.runCommand "app-src" {} ''
    mkdir $out
    cp ${./pyproject.toml} $out/pyproject.toml
    mkdir $out/app
    touch $out/app/__init__.py
  '';
});
```

## External resources

- [builtins.filterSource](https://nix.dev/manual/nix/latest/language/builtins#builtins-filterSource)
- [lib.cleanSource](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.sources.cleanSource)
- [Working with local files (fileset)](https://nix.dev/tutorials/working-with-local-files.html)
