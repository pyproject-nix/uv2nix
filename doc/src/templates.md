# Flake Templates

## hello-world

A minimal example using uv2nix for both development & packaging.

```
nix flake init --template github:pyproject-nix/uv2nix#hello-world
```

## hello-tkinter

Building on on the `hello-world` template, adding a dependency on the [tkinter](https://docs.python.org/3/library/tkinter.html) graphics library.

Tkinter is normally shipped with Python and not published on PyPI.
For closure size reasons nixpkgs splits out `tkinter` to it's own separate package in the nixpkgs Python package set.

```
nix flake init --template github:pyproject-nix/uv2nix#hello-tkinter
```

## inline-metadata

Use uv2nix with locked [inline metadata scripts](https://docs.astral.sh/uv/#scripts).

```
nix flake init --template github:pyproject-nix/uv2nix#inline-metadata
```
