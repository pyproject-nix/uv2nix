# Dependency conflicts

Uv has support for creating mutually exclusive groups of [conflicting dependencies](https://docs.astral.sh/uv/concepts/projects/config/#conflicting-dependencies).

To use conflicting dependencies with uv2nix you have to tell it which conflict resolution to take when creating the package overlay:
```nix
workspace.mkPyprojectOverlay {
  sourcePreference = "wheel";
  dependencies = {
    hello-world = [ "extra1" ];
  };
}
```

1. [Uv pull request #4339](https://github.com/astral-sh/uv/pull/4339)
2. [PEP-508 environment markers](https://packaging.python.org/en/latest/specifications/dependency-specifiers/#environment-markers)
