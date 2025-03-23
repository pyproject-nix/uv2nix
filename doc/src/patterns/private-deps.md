# Using private (authenticated) dependencies

Uv2nix uses [pkgs.fetchurl](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-fetchers-fetchurl) for fetching from PyPI, and inherits authentication support from nixpkgs.

Getting authentication running in the sandbox requires some system setup.

## Project setup

``` toml
[project]
name = "with-private-deps"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["iniconfig"]

[[tool.uv.index]]
name = "my-index"
url = "https://pypi-proxy.fly.dev/basic-auth/simple"
explicit = true

[tool.uv.sources]
iniconfig = { index = "my-index" }

[build-system]
requires = ["setuptools>=42"]
build-backend = "setuptools.build_meta"
```

## Creating a [netrc](https://everything.curl.dev/usingcurl/netrc.html) file

In this documentation we assume that the netrc file is saved as `/etc/nix/netrc`.

```
machine pypi-proxy.fly.dev
login public
password heron
```

To use this netrc file inside our development shell run:

`$ export NETRC=/etc/nix/netrc`

## Overriding source fetching

While `pkgs.fetchurl` can use a netrc file, it won't do so by default.
We'll need to override our authenticated package's `src` attribute to use our provided file.

``` nix
let
  pyprojectOverrides = _final: prev: {
    iniconfig = prev.iniconfig.overrideAttrs(old: {
      src = old.src.overrideAttrs(_: {
        # Make curl use our netrc file.
        curlOpts = "--netrc-file /etc/nix/netrc";
        # By default pkgs.fetchurl will fetch _without_ TLS verification for reproducibility.
        # Since we are transferring credentials we want to verify certificates.
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      });
    });
  };
in ...
```

## Building

To build a package we need to provide our netrc file _inside_ the Nix sandbox.

`nix build -L -v --option extra-sandbox-paths /etc/nix/netrc`

For a persistent setup `extra-sandbox-paths` should be added to `nix.conf`.
