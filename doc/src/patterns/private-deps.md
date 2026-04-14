# Using private (authenticated) dependencies

This page covers two related cases:

- authenticated package indexes and artifact URLs
- authenticated Git dependencies

Uv2nix uses [pkgs.fetchurl](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-fetchers-fetchurl) for fetching from PyPI, and inherits authentication support from nixpkgs.

For Git dependencies, uv2nix can optionally map well-known forge URLs like GitHub and GitLab to Nix's forge-aware fetchers. For public repositories this behaves like an ordinary forge fetch. For private repositories it can let Nix use [`access-tokens`](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-access-tokens) from `nix.conf`, instead of relying on `netrc` files or Git credential helpers for `builtins.fetchGit`.

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

## Private Git dependencies via `access-tokens`

When a package in `uv.lock` has a Git source such as:

```toml
source = { git = "https://github.com/my-org/private-lib.git?tag=v1.2.3#0123456789abcdef0123456789abcdef01234567" }
```

To opt in, set:

```nix
config.git-fetcher = "auto";
```

In `auto` mode uv2nix can detect the forge from the URL and prefer Nix's forge-aware fetcher.

With this in `nix.conf`:

```ini
access-tokens = github.com=ghp_xxxxxxxxxxxxxxxxxxxx gitlab.example.com=PAT:glpat-xxxxxxxxxxxxxxxxxxxx
```

Nix can authenticate those fetches without extra Git-specific credential configuration.

The default remains `git-fetcher = "git"`, which keeps using `builtins.fetchGit` with submodule-friendly behavior. This avoids changing behavior for existing projects and is the safer choice if a repository depends on Git submodules.

For self-hosted forges, also tell uv2nix which host belongs to which forge:

```nix
config = {
  git-fetcher = "auto";
  git-forge-hosts."gitlab.example.com" = "gitlab";
};
```

If you enable `auto` globally but need one repository to keep using `fetchGit`, add it to `git-fetcher-force-git`:

```nix
config = {
  git-fetcher = "auto";
  git-fetcher-force-git = [
    "github.com/my-org/private-lib"
    "gitlab.example.com/company/platform/internal-package"
  ];
};
```

Use this for repositories that require Git-specific behavior such as submodules. In that case you will still need Git-compatible credentials for `fetchGit`.

Unknown Git hosts still fall back to `builtins.fetchGit`.
