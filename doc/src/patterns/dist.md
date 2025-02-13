# Building redistributable wheels/sdists

Uv2nix can not just build environments and applications, it can also build redistributable wheels:
``` nix
pythonSet.hello-world.override {
  pyprojectHook = pythonSet.pyprojectDistHook;
}
```

Because of the risk of Nix store path references ending up in the wheel file via references to shared libraries & other Nix/nixpkgs specific behaviour the outputs are scanned for Nix store path references, and the build will fail if any are found.

## Building sdists

By default `pyproject.nix`'s builders will produce a wheel.

If you want to distribute an sdist instead override `uvBuildType`:
``` nix
(pythonSet.hello-world.override {
  pyprojectHook = pythonSet.pyprojectDistHook;
}).overrideAttrs(old: {
  env.uvBuildType = "sdist";
})
```
