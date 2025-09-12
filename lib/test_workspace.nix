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

in
{
  # Test workspace discovery - verifies workspace detection
  discoverWorkspace = {
    # Test implicit workspace (single package)
    testImplicitWorkspace = {
      expr = workspace.discoverWorkspace { workspaceRoot = ./fixtures/trivial; };
      expected = [ "/" ];
    };

    # Test explicit workspace with members
    testExplicitWorkspace = {
      expr = workspace.discoverWorkspace { workspaceRoot = ./fixtures/workspace; };
      expected = [ "/packages/workspace-package" "/" ];
    };

    # Test flat workspace layout (packages at root level)
    testFlatWorkspace = {
      expr = workspace.discoverWorkspace { workspaceRoot = ./fixtures/workspace-flat; };
      expected = [ "/packages/pkg-a" "/packages/pkg-b" ];
    };

    # Test workspace with excluded members
    testWorkspaceWithExcluded = {
      expr = workspace.discoverWorkspace { workspaceRoot = ./fixtures/workspace-with-excluded; };
      expected = [ "/packages/included-package" ];
    };
  };

  # Test workspace configuration loading
  loadConfig = {
    testTrivial = {
      expr = let
        members = workspace.discoverWorkspace { workspaceRoot = ./fixtures/trivial; };
        pyprojects = map (_m: lib.importTOML (./fixtures/trivial + "/pyproject.toml")) members;
      in workspace.loadConfig pyprojects;
      expected = { no-binary = false; no-binary-package = [ ]; no-build = false; no-build-package = [ ]; };
    };
    testWorkspace = {
      expr = let
        members = workspace.discoverWorkspace { workspaceRoot = ./fixtures/workspace; };
        pyprojects = map (_m: lib.importTOML (./fixtures/workspace + "/pyproject.toml")) members;
      in workspace.loadConfig pyprojects;
      expected = { no-binary = false; no-binary-package = [ ]; no-build = false; no-build-package = [ ]; };
    };
    testWorkspaceFlat = {
      expr = let
        members = workspace.discoverWorkspace { workspaceRoot = ./fixtures/workspace-flat; };
        pyprojects = map (_m: lib.importTOML (./fixtures/workspace-flat + "/pyproject.toml")) members;
      in workspace.loadConfig pyprojects;
      expected = { no-binary = false; no-binary-package = [ ]; no-build = false; no-build-package = [ ]; };
    };
  };

  # Test workspace loading and member functionality
  loadWorkspace = {
    # Test 1: Basic workspace with root + members (albatross + bird-feeder example)
    testBasicWorkspaceWithMembers = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace; };
      in {
        # Verify workspace members are detected correctly
        members = ws.members;
        memberCount = builtins.length ws.members;
        # Verify root is included as a member
        hasRoot = builtins.elem "workspace" ws.members;
        # Verify package member is included
        hasPackage = builtins.elem "workspace-package" ws.members;
      };
      expected = {
        members = [ "workspace" "workspace-package" ];
        memberCount = 2;
        hasRoot = true;
        hasPackage = true;
      };
    };

    # Test 2: Workspace with excluded members (seeds example)
    testWorkspaceWithExcludedMembers = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace-with-excluded; };
      in {
        members = ws.members;
        memberCount = builtins.length ws.members;
        # Verify excluded member is not included
        hasExcluded = builtins.elem "excluded-package" ws.members;
        # Verify included member is present
        hasIncluded = builtins.elem "included-package" ws.members;
      };
      expected = {
        members = [ "included-package" ];
        memberCount = 1;
        hasExcluded = false;
        hasIncluded = true;
      };
    };

    # Test 3: Flat workspace layout (packages at root level)
    testFlatWorkspaceLayout = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace-flat; };
      in {
        members = ws.members;
        memberDeps = ws.memberDeps;
        # Test dependency resolution between members
        pkgBDeps = ws.getMemberDeps "pkg-b";
      };
      expected = {
        members = [ "pkg-a" "pkg-b" ];
        memberDeps = {
          "pkg-a" = {
            default = [ ];
            optionals = [ ];
            groups = [ ];
            all = [ ];
          };
          "pkg-b" = {
            default = [ "pkg-a" ];
            optionals = [ ];
            groups = [ ];
            all = [ ];
          };
        };
        pkgBDeps = {
          default = [ "pkg-a" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
      };
    };

    # Test 4: Complex workspace with multiple dependencies (FastAPI + libraries example)
    testComplexWorkspaceWithDependencies = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace-members; };
      in {
        members = ws.members;
        # Test dependency resolution between members
        webappDeps = ws.getMemberDeps "webapp";
        apiDeps = ws.getMemberDeps "api";
        sharedDeps = ws.getMemberDeps "shared";
        # Test member info
        webappInfo = ws.getMemberInfo "webapp";
        apiInfo = ws.getMemberInfo "api";
        sharedInfo = ws.getMemberInfo "shared";
      };
      expected = {
        members = [ "api" "shared" "webapp" ];
        webappDeps = {
          default = [ "flask" "requests" "shared" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
        apiDeps = {
          default = [ "fastapi" "shared" "uvicorn" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
        sharedDeps = {
          default = [ "click" "pydantic" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
        webappInfo = {
          name = "webapp";
          version = "0.1.0";
          path = "packages/webapp";
          source = { editable = "packages/webapp"; };
          dependencies = [ "flask" "requests" "shared" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
        apiInfo = {
          name = "api";
          version = "0.1.0";
          path = "packages/api";
          source = { editable = "packages/api"; };
          dependencies = [ "fastapi" "shared" "uvicorn" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
        sharedInfo = {
          name = "shared";
          version = "0.1.0";
          path = "packages/shared";
          source = { editable = "packages/shared"; };
          dependencies = [ "click" "pydantic" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
      };
    };

    # Test 5: Workspace member listing functionality
    testMemberListing = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace; };
      in {
        # Test listMembers alias
        listMembers = ws.listMembers;
        # Test members attribute
        members = ws.members;
        # Verify they are the same
        membersEqual = ws.listMembers == ws.members;
      };
      expected = {
        listMembers = [ "workspace" "workspace-package" ];
        members = [ "workspace" "workspace-package" ];
        membersEqual = true;
      };
    };

    # Test 6: Error handling for non-existent members
    testErrorHandling = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace; };
      in {
        # Test getMemberDeps with non-existent member
        invalidMemberDeps = builtins.tryEval (ws.getMemberDeps "nonexistent");
        # Test getMemberInfo with non-existent member
        invalidMemberInfo = builtins.tryEval (ws.getMemberInfo "nonexistent");
      };
      expected = {
        invalidMemberDeps = { success = false; value = false; };
        invalidMemberInfo = { success = false; value = false; };
      };
    };

    # Test 7: Workspace root detection and member dependencies
    testWorkspaceRootAndDependencies = {
      expr = let
        ws = workspace.loadWorkspace { workspaceRoot = ./fixtures/workspace; };
      in {
        # Test root member info
        rootInfo = ws.getMemberInfo "workspace";
        # Test root member dependencies
        rootDeps = ws.getMemberDeps "workspace";
        # Test package member info
        packageInfo = ws.getMemberInfo "workspace-package";
        # Test package member dependencies
        packageDeps = ws.getMemberDeps "workspace-package";
      };
      expected = {
        rootInfo = {
          name = "workspace";
          version = "0.1.0";
          path = ".";
          source = { editable = "."; };
          dependencies = [ "workspace-package" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
        rootDeps = {
          default = [ "workspace-package" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
        packageInfo = {
          name = "workspace-package";
          version = "0.1.0";
          path = "packages/workspace-package";
          source = { editable = "packages/workspace-package"; };
          dependencies = [ "arpeggio" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
        packageDeps = {
          default = [ "arpeggio" ];
          optionals = [ ];
          groups = [ ];
          all = [ ];
        };
      };
    };
  };
}
