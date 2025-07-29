# Advanced build systems (editables)

When using more advanced build systems, such as `cython` which builds native dependencies, or `meson-python` which relies on import hooks to dynamically perform recompilation on import an additional step needs to be taken to bridge the gap between the sandboxed Nix build and the source tree:
```nix
pkgs.mkShell {
  packages = [
    virtualenv
    pkgs.uv

    # Add build-editable package from pyproject.nix
    pyproject-nix.packages.${system}.build-editable
  ];

  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = python.interpreter;
    UV_PYTHON_DOWNLOADS = "never";
  };

  shellHook = ''
    unset PYTHONPATH
    export REPO_ROOT=$(git rev-parse --show-toplevel)

    # Re-run editable package build for side effects
    build-editable
  '';
};
```

Whenever you want to perform a build invoke `build-editable` which will in turn invoke your build system and write side effects such as `.so`'s in-place in your source tree.
For most (all?) pure-Python build systems this is not relevant.
