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

      testWorkspaceMembers = {
        expr = mkTest ./fixtures/workspace;
        expected = {
          all = {
            workspace = [ ];
            "workspace-package" = [ ];
          };
          groups = {
            workspace = [ ];
            "workspace-package" = [ ];
          };
          optionals = {
            workspace = [ ];
            "workspace-package" = [ ];
          };
          default = {
            workspace = [ ];
            "workspace-package" = [ ];
          };
          # Member-specific dependencies
          "workspace-package" = {
            default = [ "arpeggio" ];
            optionals = [ ];
            groups = [ ];
            all = [ ];
          };
          workspace = {
            default = [ "workspace-package" ];
            optionals = [ ];
            groups = [ ];
            all = [ ];
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
    };

  # Test new member-specific functionality
  loadWorkspace.members =
    let
      mkTest = workspaceRoot: workspace.loadWorkspace { inherit workspaceRoot; };
    in
    {
      testWorkspaceMembers = {
        expr = (mkTest ./fixtures/workspace).members;
        expected = [ "workspace-package" "workspace" ];
      };
      
      testWorkspaceFlatMembers = {
        expr = (mkTest ./fixtures/workspace-flat).members;
        expected = [ "pkg-a" "pkg-b" ];
      };
    };

  loadWorkspace.getMemberDeps =
    let
      mkTest = workspaceRoot: workspace.loadWorkspace { inherit workspaceRoot; };
    in
    {
      testWorkspacePackageDeps = {
        expr = (mkTest ./fixtures/workspace).getMemberDeps "workspace-package";
        expected = {
          default = [ "arpeggio" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
      };
      
      testPkgBDeps = {
        expr = (mkTest ./fixtures/workspace-flat).getMemberDeps "pkg-b";
        expected = {
          default = [ "pkg-a" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
      };
    };

  loadWorkspace.getMemberInfo =
    let
      mkTest = workspaceRoot: workspace.loadWorkspace { inherit workspaceRoot; };
    in
    {
      testWorkspacePackageInfo = {
        expr = (mkTest ./fixtures/workspace).getMemberInfo "workspace-package";
        expected = {
          name = "workspace-package";
          path = "/packages/workspace-package";
          version = "0.1.0";
          description = "Add your description here";
          dependencies = {
            dependencies = [ "arpeggio" ];
            optional-dependencies = { };
            dev-dependencies = { };
          };
          pyproject = {
            project = {
              name = "workspace-package";
              version = "0.1.0";
              description = "Add your description here";
              readme = "README.md";
              requires-python = ">=3.12";
              dependencies = [ "arpeggio" ];
            };
            build-system = {
              requires = [ "hatchling" ];
              build-backend = "hatchling.build";
            };
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

  # Additional tests for workspace member features
  loadWorkspace.memberFeatures =
    let
      testWorkspace = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace; };
    in
    {
      # Test listMembers alias
      testListMembersAlias = {
        expr = testWorkspace.listMembers;
        expected = testWorkspace.members;
      };

      # Test error handling for non-existent member in getMemberDeps
      testNonExistentMemberDeps = {
        expr = builtins.tryEval (testWorkspace.getMemberDeps "nonexistent");
        expected = { success = false; value = false; };
      };

      # Test error handling for non-existent member in getMemberInfo
      testNonExistentMemberInfo = {
        expr = builtins.tryEval (testWorkspace.getMemberInfo "nonexistent");
        expected = { success = false; value = false; };
      };
    };


}

