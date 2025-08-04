# Building redistributable wheels/sdists

## Building wheels

As a part of building a Python package `uv2nix` builds a wheel which is installed into the Nix store.
The intermediate wheel file is normally discarded once the build is complete and the wheel has been installed into it's Nix store prefix.

### Using multiple outputs

Using [multiple outputs](https://nixos.org/manual/nixpkgs/stable/#chap-multiple-output) allows us to not only perform our regular install steps, but also to install the wheel files into a separate output.
To add a separate dist output:
```nix
pythonSet.hello-world.override (old: {
  outputs = [ "out" dist" ];
})
```
This will install the produced wheel into the build output directory of the `dist` output, producing the same contents as a `uv build` would produce in `dist/`.

### Augmenting install behaviour

To augment the install behaviour to install the produced wheel into the Nix store output by overriding our package:
``` nix
pythonSet.hello-world.override {
  pyprojectHook = pythonSet.pyprojectDistHook;
}
```
This will install the produced wheel into the build output directory, producing the same contents as a `uv build` would produce in `dist/`.
Note that this method will not perform the regular `pyproject.nix` install steps, making the output unsuitable for usage with `mkVirtualEnv`.

<div class="warning">
Because of the risk of Nix store path references ending up in the wheel file via references to shared libraries & other Nix/nixpkgs specific behaviour the outputs are scanned for Nix store path references, and the build will fail if any are found.
</div>

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
