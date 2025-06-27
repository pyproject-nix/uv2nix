{
  workspace,
  pkgs,
  lib,
  pyproject-nix,
  ...
}:

let
  inherit (lib) nameValuePair;
  inherit (import ./testutil.nix { inherit lib; }) capitalise;

  # Test fixture workspaces
  workspaces = {
    trivial = ./fixtures/trivial;
    workspace = ./fixtures/workspace;
    workspaceFlat = ./fixtures/workspace-flat;
    no-build-no-binary-packages = ./fixtures/no-build-no-binary-packages;
    no-build = ./fixtures/no-build;
    no-binary = ./fixtures/no-binary;
    no-binary-no-build = ./fixtures/no-binary-no-build;
    withLegacy = ./fixtures/workspace-with-legacy;
  };

in
{
  discoverWorkspace =
    let
      test = workspaceRoot: expected: {
        expr = workspace.discoverWorkspace { inherit workspaceRoot; };
        inherit expected;
      };
    in
    {
      testImplicitWorkspace = test workspaces.trivial [ "/" ];
      testWorkspace = test workspaces.workspace [
        "/packages/workspace-package"
        "/"
      ];
      testWorkspaceFlat = test workspaces.workspaceFlat [
        "/packages/pkg-a"
        "/packages/pkg-b"
      ];
      testWorkspaceExcluded = test ./fixtures/workspace-with-excluded [ "/packages/included-package" ];
    };

  loadConfig = lib.mapAttrs' (
    name': root:
    let
      name = "test${capitalise name'}";
      members = workspace.discoverWorkspace { workspaceRoot = root; };
      pyprojects = map (_m: lib.importTOML (root + "/pyproject.toml")) members;
      config = workspace.loadConfig pyprojects;
    in
    nameValuePair name {
      expr = config;
      expected = lib.importJSON ./expected/workspace.loadConfig.${name}.json;
    }
  ) workspaces;

  loadWorkspace.deps =
    let
      mkTest =
        workspaceRoot:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };
        in
        ws.deps;
    in
    {
      testTrivial = {
        expr = mkTest ./fixtures/trivial;
        expected = {
          all = {
            trivial = [ ];
          };
          groups = {
            trivial = [ ];
          };
          optionals = {
            trivial = [ ];
          };
          default = {
            trivial = [ ];
          };
        };
      };

      testOptionalDeps = {
        expr = mkTest ./fixtures/optional-deps;
        expected = rec {
          optionals = {
            optional-deps = [ "haxx" ];
          };
          all = optionals;
          groups = {
            optional-deps = [ ];
          };
          default = {
            optional-deps = [ ];
          };
        };
      };

      testDependencyGroups = {
        expr = mkTest ./fixtures/dependency-groups;
        expected = rec {
          all = groups;
          groups = {
            dependency-groups = [
              "dev"
              "group-a"
            ];
          };
          optionals = {
            dependency-groups = [ ];
          };
          default = {
            dependency-groups = [ ];
          };
        };
      };

      testConflictingDependencyGroups = {
        expr = mkTest ./fixtures/dependency-group-conflicts;
        expected = rec {
          all = groups;
          groups = {
            dependency-group-conflicts = [
              "group-a"
              "group-b"
              "group-c"
            ];
          };
          optionals = {
            dependency-group-conflicts = [ ];
          };
          default = {
            dependency-group-conflicts = [ ];
          };
        };
      };
    };

  # Test workspaceRoot passed as a string
  # This is analogous to using Flake inputs which are passed as contextful strings.
  loadWorkspace.stringlyWorkspace =
    let
      mkTestSet =
        workspaceRoot:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };

          overlay = ws.mkPyprojectOverlay { sourcePreference = "wheel"; };

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              overlay;
        in
        pythonSet;

      wsRoot = "${./fixtures/workspace-flat}";
      testSet = mkTestSet wsRoot;

    in
    {
      # Test that the stringly src lookup is correct relative to the workspace root
      testStringlySrc = {
        expr = testSet."pkg-a".src == "${wsRoot}/packages/pkg-a";
        expected = true;
      };
    };

  # Test workspaceRoot passed as an attrset
  # This is analogous to using builtins.fetchGit & such which return an attrset with an outPath member.
  loadWorkspace.fetchedWorkspace =
    let
      mkTestSet =
        workspaceRoot:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };

          overlay = ws.mkPyprojectOverlay { sourcePreference = "wheel"; };

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              overlay;
        in
        pythonSet;

      wsRoot = {
        outPath = "${./fixtures/workspace-flat}";
      };
      testSet = mkTestSet wsRoot;
    in
    {
      # Test that the stringly src lookup is correct relative to the workspace root
      testOutpathSrc = {
        expr = testSet."pkg-a".src == "${wsRoot}/packages/pkg-a";
        expected = true;
      };
    };

}
