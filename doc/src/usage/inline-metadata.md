# Inline metadata

Uv supports [locking dependencies](https://docs.astral.sh/uv/guides/scripts/#locking-dependencies) for [inline metadata](https://packaging.python.org/en/latest/specifications/inline-script-metadata/#inline-script-metadata) scripts.

This example shows you how to set up a `uv2nix` from a directory of locked scripts.

It has the following features:
- Creating one Python package set per script from `${script}.py.lock`

- Build each script with `nix build .#script`

- Run each script with `nix run .#script`

## flake.nix
```nix
{{#include ../../../templates/inline-metadata/flake.nix}}
```
## scripts/example.py
```nix
{{#include ../../../templates/inline-metadata/scripts/example.py}}
```
