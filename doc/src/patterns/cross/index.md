# Cross compilation

## Overriding build systems

When cross compiling build systems needs to be overriden _twice_.
Once for the _build host_ and once for the _target host_

```nix
{{#include ./build-systems.nix}}
```

## Adding native build dependencies

```nix
{{#include ./build-depends.nix}}
```
