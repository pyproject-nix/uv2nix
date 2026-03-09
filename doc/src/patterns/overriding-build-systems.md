# Overriding build systems

Overriding build systems is required in `uv2nix` when building packages from `sdist`, as [`uv` doesn't lock build systems](https://github.com/astral-sh/uv/issues/5190).

## Using tool.uv.extra-build-dependencies

Uv supports adding additional build systems declaratively through `pyproject.toml`:

[https://docs.astral.sh/uv/reference/settings/#extra-build-dependencies]()

This is automatically picked up by `uv2nix`.

## Using a manual overlay

Overriding many build systems manually can quickly become tiresome with repeated declarations of `nativeBuildInputs` & calls to `resolveBuildSystem` for every package.

This overlay shows one strategy to deal with many build system overrides in a declarative fashion.

```nix
{{#include ../../../dev/build-system-overrides.nix}}
```
