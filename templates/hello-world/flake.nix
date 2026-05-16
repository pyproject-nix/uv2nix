{
  description = "hello world application using uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = {
    nixpkgs,
    pyproject-nix,
    uv2nix,
    pyproject-build-systems,
    ...
  }: let
    inherit (nixpkgs) lib;

    wrapDefault = x: {default = x;};

    forAllSystems = f: let
      byAllSystems = lib.genAttrs lib.systems.flakeExposed;
      perSystem = system: f nixpkgs.legacyPackages.${system};
    in
      byAllSystems perSystem;

    workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

    overlay = workspace.mkPyprojectOverlay {sourcePreference = "wheel";};

    editableOverlay = workspace.mkEditablePyprojectOverlay {root = "$REPO_ROOT";};

    pythonSets = let
      mkPythonSet = pkgs: let
        python = lib.head (pyproject-nix.lib.util.filterPythonInterpreters {
          inherit (workspace) requires-python;
          inherit (pkgs) pythonInterpreters;
        });
        pythonBase = pkgs.callPackage pyproject-nix.build.packages {inherit python;};
      in
        pythonBase.overrideScope (lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          overlay
        ]);
    in
      forAllSystems mkPythonSet;
  in {
    devShells = let
      mkDevShell = pkgs: let
        editablePythonSet =
          pythonSets.${pkgs.stdenv.hostPlatform.system}.overrideScope editableOverlay;
        virtualenv =
          editablePythonSet.mkVirtualEnv "hello-world-dev-env" workspace.deps.all;
      in
        wrapDefault (pkgs.mkShell {
          packages = [
            virtualenv
            pkgs.uv
          ];
          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = editablePythonSet.python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
          };
          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        });
    in
      forAllSystems mkDevShell;

    packages = let
      mkPackages = pkgs: let
        mkVenv = pythonSets.${pkgs.stdenv.hostPlatform.system}.mkVirtualEnv "hello-world-env";
      in
        wrapDefault (mkVenv workspace.deps.default);
    in
      forAllSystems mkPackages;
  };
}
