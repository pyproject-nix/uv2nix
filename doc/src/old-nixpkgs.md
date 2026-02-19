# Using uv2nix with older nixpkgs versions

`uv2nix` supports nixpkgs `>=22.11`, but requires additional manual overrides for nixpkgs `<=24.11`.

The `pyproject.nix` build hooks require a more recent version of `uv`(`>=0.5.7`) on older channels, which needs to be added via a nixpkgs overlay like:
```nix
import nixpkgs {
    overlays = [
      (final: prev: {
        uv = inputs.uv2nix.packages.${system}.uv-bin;
      })
    ];
}
```
