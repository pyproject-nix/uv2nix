{
  description = "Pyproject.nix CI deps";

  inputs = {
    nix-github-actions = {
      url = "github:nix-community/nix-github-actions";
      flake = false;
    };

    flake-compat = {
      url = "https://git.lix.systems/lix-project/flake-compat/archive/main.tar.gz";
      flake = false;
    };

    nixpkgs-22_11.url = "github:nixos/nixpkgs/nixos-22.11";
  };

  outputs = { ... }: { };
}
