# Installing packages from nixpkgs not in PyPI

In some cases a package isn't published on PyPI, but is packaged in nixpkgs.
One such package is the `seccomp` package.

## Installing a wheel (recommended)

By using [`UV_FIND_LINKS`](https://docs.astral.sh/uv/configuration/environment/#uv_find_links) and a `shellHook` we can install the nixpkgs built wheel, making it possible to use both impure (uv managed) workflows & pure uv2nix managed workflows.

``` nix
let
  python = pkgs.python3;

  uv-links = pkgs.symlinkJoin {
    name = "uv-links";
    paths = [
      # Note: Using the dist output which contains a wheel
      python.pkgs.seccomp.dist
    ];
  };

in
mkShell {
  packages = [ pkgs.uv python ];
  shellHook = ''
    ln -sfn ${uv-links} .uv-links
    export UV_FIND_LINKS=$(realpath -s .uv-links)
  '';
}
```

To be able to read the sources from a Flake evaluation you will also have to override the `seccomp` package sources, as `.uv-links` is not added to Git.

``` nix
let
  pyprojectOverrides = final: prev: {
    seccomp = prev.seccomp.overrideAttrs(old: {
      buildInputs = (old.buildInputs or []) ++ python.pkgs.seccomp.buildInputs;
      src = python.pkgs.seccomp.dist;
    });
  };
in ...
```

## Using [pyproject.nix hacks](https://pyproject-nix.github.io/pyproject.nix/builders/hacks.html#using-prebuilt-packages-from-nixpkgs)

It's also possible to skip making uv aware of the package and only add the nixpkgs package from a Nix evaluation.

``` nix
let
  pyprojectOverrides = final: prev: {
    seccomp = hacks.nixpkgsPrebuilt {
      from = python.pkgs.seccomp;
    };
  };

  pythonSet' = pythonSet.overrideScope pyprojectOverrides;
in
  pythonSet.mkVirtualEnv "seccomp-env" {
    seccomp = [ ];
  }
```
