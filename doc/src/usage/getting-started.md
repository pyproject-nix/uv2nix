# Getting started with uv2nix

Before going further and adopting uv2nix, first consider if you really want/need it.
You don't need uv2nix to develop uv projects with Nix.

If you are not deploying your application with Nix it's likely that you don't want uv2nix and might be fine using the [`impure` template from `pyproject.nix`](https://pyproject-nix.github.io/pyproject.nix/templates.html#impure):
```
nix flake init --template github:pyproject-nix/pyproject.nix#impure
```

It's also possible that you might want to develop your package(s) in an impure shell (as opposed to using editables with uv2nix, see development shell below), but deploy using uv2nix.

Any combination of approaches is possible, with different trade-offs for each.

## Reading along

This getting started guide is intended to be read alongside the `hello-world` [uv2nix template](../templates.html):
```
nix flake init --template github:pyproject-nix/uv2nix#hello-world
```

which contains much of the same code, but without elaboration or explanation of all the involved concepts.

## Creating a pyproject.toml & uv.lock

Before anything can be done enter a development shell with required bootstrapping dependencies:
```
nix-shell -p python3 uv
```

And then use uv to create a boilerplate `pyproject.toml` & a `uv.lock`:
```
uv init --app --package
uv lock
```

You can now start [adding dependencies](https://docs.astral.sh/uv/#projects) & more.

## Using pyproject.nix/uv2nix

### Constructing a base Python set

Uv2nix uses [`pyproject.nix` Python builders](https://pyproject-nix.github.io/pyproject.nix/build.html) which needs to be instantiated with a nixpkgs instance:
```nix
pythonBase = pkgs.callPackage pyproject-nix.build.packages {
  inherit python;
};
```

Creates the necessary structure & build hooks, but it doesn't contain any Python packages itself.
In uv2nix all Python packages are generated from `uv.lock` & explicitly added through [overlays](https://nixos.org/manual/nixpkgs/unstable/#chap-overlays).

### Loading a uv workspace


The top-level abstraction in uv2nix is the [_workspace_](https://docs.astral.sh/uv/concepts/projects/workspaces/), which needs to be loaded.

```nix
workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
```

Will recursively discover, load & parse all necessary member projects in a uv workspace.

Uv2nix treats every project as a workspace project, even if it only contains a single `pyproject.toml` with a single project.

### Creating a uv2nix generated overlay

Takes `uv.lock` & creates an overlay for use with `pyproject.nix` builders.

```nix
overlay = workspace.mkPyprojectOverlay {
  sourcePreference = "wheel";
};
```

With `sourcePreference` you have a choice to make:

- `wheel`

Prefer downloading packages as binary wheels.

- `sdist`

Prefer building packages from source.

Binary wheels are much more likely to "just work" while sdists require manual [overrides](../overriding/index.html) more often.
Wheel/sdist selection can also be done on a per-package basis.

If you are experiencing uv2nix using an sdist where you expect it to use a wheel on MacOS you might need to set the appropriate [platform quirks](https://pyproject-nix.github.io/uv2nix/platform-quirks.html).

### Notes on build systems

uv [doesn't lock build systems](https://github.com/astral-sh/uv/issues/5190) which are required when building packages from source.
uv2nix doesn't try to hide this definiency, but instead has an [overlay with the most common ones provided](https://github.com/pyproject-nix/build-system-pkgs).

The build system overlay has the same sdist/wheel distinction as `mkPyprojectOverlay`:

- `pyproject-build-systems.overlays.wheel`

Prefer build systems from binary wheels

- `pyproject-build-systems.overlays.sdist`

Prefer build systems packages from source

### Gluing everything together into a package set

Compose the Python base set + build systems + `uv.lock` generated packages into a concrete Python set:

```nix
pythonSet = pythonBase.overrideScope (
  lib.composeManyExtensions [
    pyproject-build-systems.overlays.wheel
    overlay
  ]
);
```

This set contains all Python packages as individual attributes.

### Building a virtual environment

Uv2nix [builds packages individually](https://pyproject-nix.github.io/pyproject.nix/build.html#solution-presented-by-pyprojectnixs-builders), but they aren't really useful until they're aggregated into a virtual environment.

The most convienent way to build a virtualenv is to use one of the dependency presets:
```nix
pythonSet.mkVirtualEnv "hello-world-env" workspace.deps.default
```

But it's also possible to specify which dependencies to install explicitly:
```nix
pythonSet.mkVirtualEnv "hello-world-env" {
  # Install hello-world with no enabled extras
  hello-world = [ ];
}
```

To ship package where the virtualenv is hidden see [shipping applications](../patterns/applications.html).

### Setting up a development environment (optional)

When developing Python packages local packages are normally installed in [editable mode](https://setuptools.pypa.io/en/latest/userguide/development_mode.html).
Editable packages make [entry points](https://packaging.python.org/en/latest/specifications/pyproject-toml/#entry-points) like `scripts` available in the virtual environment, but instead of installed Python files the virtualenv contains pointers to the source tree.
This means that changes to the sources are immeditately activated and doesn't require a rebuild.

Uv2nix supports editable packages, but requires you to generate a separate overlay & package set for them:
```nix
editableOverlay = workspace.mkEditablePyprojectOverlay {
  # Use environment variable pointing to editable root directory
  root = "$REPO_ROOT";
  # Optional: Only enable editable for these packages
  # members = [ "hello-world" ];
};

editablePythonSet = pythonSet.overrideScope editableOverlay;

virtualenv = editablePythonSet.mkVirtualEnv "hello-world-dev-env" workspace.deps.all;
```

The virtualenv can then be used with [`mkShell`](https://nixos.org/manual/nixpkgs/unstable/#sec-pkgs-mkShell):

```nix
pkgs.mkShell {
  packages = [
    virtualenv
    pkgs.uv
  ];

  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = editablePythonSet.python.interpreter;
    UV_PYTHON_DOWNLOADS = "never";
  };

  shellHook = ''
    unset PYTHONPATH
    export REPO_ROOT=$(git rev-parse --show-toplevel)
  '';
}
```

The `env` attribute contains these settings:
- `UV_NO_SYNC`

  Prevent uv from managing a virtual environment, this is managed by uv2nix.

- `UV_PYTHON`

  Use interpreter path for all uv operations.

- `UV_PYTHON_DOWNLOADS`

  Prevent uv from downloading [managed Python interpreters](https://docs.astral.sh/uv/#python-versions), we use Nix instead.

The `shellHook` contains two interesting pieces:

- Unsetting `PYTHONPATH`

  Unset to eliminate bad [side effects from Nixpkgs Python builders](https://pyproject-nix.github.io/pyproject.nix/build.html#pythonpath-leaking-into-unrelated-builds).

- Setting `REPO_ROOT`

  To inform the virtualenv which directory editable packages are relative to.

Some advanced build systems (like `meson-python`) are more involved & require [additional setup](../patterns/advanced-build-systems.html).
