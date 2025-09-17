# Flake Templates

## hello-world

A minimal example using uv2nix for both development & packaging.

```
nix flake init --template github:pyproject-nix/uv2nix#hello-world
```

## inline-metadata

Use uv2nix with locked [inline metadata scripts](https://docs.astral.sh/uv/#scripts).

```
nix flake init --template github:pyproject-nix/uv2nix#inline-metadata
```
