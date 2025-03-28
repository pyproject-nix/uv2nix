# Patching dependencies

With uv2nix, you can apply patches to your Python dependencies.

Use this superpower judiciously: if you're building a Python library, you probably don't want to apply patches to your dependencies that users of your library would also somehow have to apply.

## Applying a patch

This overlay applies a patch to the `arpeggio` library.

`tqdm-patch.patch`:

```diff
{{#include ../../../dev/arpeggio.patch}}
```

Note how the overlay forces us to build from sdist, which requires specifying the build system. See [Overriding build systems](./overriding-build-systems.md) for more details.

```nix
{{#include ../../../dev/patching-deps.nix}}
```
