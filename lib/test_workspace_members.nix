{
  workspace,
  pkgs,
  lib,
  pyproject-nix,
  ...
}:

let
  inherit (lib) nameValuePair;

  # Test fixture workspaces
  workspaces = {
    workspace = ./fixtures/workspace;
    workspaceFlat = ./fixtures/workspace-flat;
    workspaceWithLegacy = ./fixtures/workspace-with-legacy;
    workspaceWithExcluded = ./fixtures/workspace-with-excluded;
    workspaceMembersTest = ./fixtures/workspace-members-test;
    simpleWorkspace = ./fixtures/simple-workspace;
  };

in
{
  # Test workspace member discovery
  discoverWorkspace.memberDiscovery =
    let
      test = workspaceRoot: expected: {
        expr = workspace.discoverWorkspace { inherit workspaceRoot; };
        expected = expected;
      };
    in
    {
      # Test standard workspace member discovery
      testStandardWorkspace = test workspaces.workspace [ "/packages/workspace-package" "/" ];
      
      # Test simple workspace member discovery
      testSimpleWorkspace = test workspaces.simpleWorkspace [ "/packages/pkg-a" "/packages/pkg-b" "/" ];
      
      # Test comprehensive workspace member discovery
      testWorkspaceMembersTest = test workspaces.workspaceMembersTest [ "/packages/webapp" "/packages/api" "/packages/shared" "/apps/cli" "/" ];
      
      # Test workspace with excluded members
      testWorkspaceWithExcluded = test workspaces.workspaceWithExcluded [ "/packages/included-package" ];
    };

  # Test member name extraction
  loadWorkspace.memberNames =
    let
      test = workspaceRoot: expected: {
        expr = (workspace.loadWorkspace { inherit workspaceRoot; }).members;
        expected = expected;
      };
    in
    {
      # Test standard workspace member names
      testStandardWorkspace = test workspaces.workspace [ "workspace-package" "workspace" ];
      
      # Test simple workspace member names
      testSimpleWorkspace = test workspaces.simpleWorkspace [ "pkg-a" "pkg-b" "simple-workspace" ];
      
      # Test comprehensive workspace member names
      testWorkspaceMembersTest = test workspaces.workspaceMembersTest [ "webapp" "api" "shared" "cli" "workspace-members-test" ];
      
      # Test workspace with excluded members
      testWorkspaceWithExcluded = test workspaces.workspaceWithExcluded [ "included-package" ];
    };

  # Test getMemberDeps functionality
  loadWorkspace.getMemberDeps =
    let
      test = workspaceRoot: memberName: expected: {
        expr = (workspace.loadWorkspace { inherit workspaceRoot; }).getMemberDeps memberName;
        expected = expected;
      };
    in
    {
      # Test workspace-package dependencies
      testWorkspacePackageDeps = test workspaces.workspace "workspace-package" {
        default = [ "arpeggio" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      # Test root workspace dependencies
      testRootWorkspaceDeps = test workspaces.workspace "workspace" {
        default = [ "workspace-package" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      # Test simple workspace member dependencies
      testPkgADeps = test workspaces.simpleWorkspace "pkg-a" {
        default = [ "requests" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      testPkgBDeps = test workspaces.simpleWorkspace "pkg-b" {
        default = [ "pkg-a" "click" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      # Test comprehensive workspace member dependencies
      testWebappDeps = test workspaces.workspaceMembersTest "webapp" {
        default = [ "flask" "shared" "requests" ];
        optionals = [ "dev" ];
        groups = [ "test" ];
        all = [ "dev" "test" ];
      };
      
      testApiDeps = test workspaces.workspaceMembersTest "api" {
        default = [ "fastapi" "shared" "uvicorn" ];
        optionals = [ "prod" ];
        groups = [ "lint" ];
        all = [ "prod" "lint" ];
      };
      
      testSharedDeps = test workspaces.workspaceMembersTest "shared" {
        default = [ "pydantic" "click" ];
        optionals = [ "all" ];
        groups = [ "docs" ];
        all = [ "all" "docs" ];
      };
      
      testCliDeps = test workspaces.workspaceMembersTest "cli" {
        default = [ "shared" "click" ];
        optionals = [ "dev" ];
        groups = [ ];
        all = [ "dev" ];
      };
      
      # Test error handling for non-existent member
      testNonExistentMember = {
        expr = builtins.tryEval ((workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).getMemberDeps "nonexistent");
        expected = { success = false; value = false; };
      };
    };

  # Test getMemberInfo functionality
  loadWorkspace.getMemberInfo =
    let
      test = workspaceRoot: memberName: expected: {
        expr = (workspace.loadWorkspace { inherit workspaceRoot; }).getMemberInfo memberName;
        expected = expected;
      };
    in
    {
      # Test workspace-package info
      testWorkspacePackageInfo = test workspaces.workspace "workspace-package" {
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
      
      # Test root workspace info
      testRootWorkspaceInfo = test workspaces.workspace "workspace" {
        name = "workspace";
        path = "/";
        version = "0.1.0";
        description = "";
        dependencies = {
          dependencies = [ "workspace-package" ];
          optional-dependencies = { };
          dev-dependencies = { };
        };
        pyproject = {
          project = {
            name = "workspace";
            version = "0.1.0";
            requires-python = ">=3.12";
            dependencies = [ "workspace-package" ];
          };
          "tool.uv.sources" = {
            "workspace-package" = { workspace = true; };
          };
          "tool.uv.workspace" = {
            members = [ "packages/*" ];
          };
          build-system = {
            requires = [ "hatchling" ];
            build-backend = "hatchling.build";
          };
        };
      };
      
      # Test error handling for non-existent member
      testNonExistentMemberInfo = {
        expr = builtins.tryEval ((workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).getMemberInfo "nonexistent");
        expected = { success = false; value = false; };
      };
    };

  # Test member-specific dependencies via deps attribute
  loadWorkspace.deps.memberDeps =
    let
      test = workspaceRoot: memberName: expected: {
        expr = (workspace.loadWorkspace { inherit workspaceRoot; }).deps."${memberName}";
        expected = expected;
      };
    in
    {
      # Test workspace-package dependencies via deps
      testWorkspacePackageDepsViaDeps = test workspaces.workspace "workspace-package" {
        default = [ "arpeggio" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      # Test root workspace dependencies via deps
      testRootWorkspaceDepsViaDeps = test workspaces.workspace "workspace" {
        default = [ "workspace-package" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      # Test flat workspace member dependencies via deps
      testPkgADepsViaDeps = test workspaces.workspaceFlat "pkg-a" {
        default = [ ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
      
      testPkgBDepsViaDeps = test workspaces.workspaceFlat "pkg-b" {
        default = [ "pkg-a" ];
        optionals = [ ];
        groups = [ ];
        all = [ ];
      };
    };

  # Test listMembers functionality
  loadWorkspace.listMembers =
    let
      test = workspaceRoot: expected: {
        expr = (workspace.loadWorkspace { inherit workspaceRoot; }).listMembers;
        expected = expected;
      };
    in
    {
      # Test listMembers for standard workspace
      testStandardWorkspace = test workspaces.workspace [ "workspace-package" "workspace" ];
      
      # Test listMembers for simple workspace
      testSimpleWorkspace = test workspaces.simpleWorkspace [ "pkg-a" "pkg-b" "simple-workspace" ];
      
      # Test listMembers for comprehensive workspace
      testWorkspaceMembersTest = test workspaces.workspaceMembersTest [ "webapp" "api" "shared" "cli" "workspace-members-test" ];
      
      # Test listMembers alias matches members
      testListMembersAlias = {
        expr = (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).listMembers;
        expected = (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).members;
      };
    };

  # Test member dependency merging
  loadWorkspace.deps.memberDepsMerging =
    {
      # Test that member deps are merged into main deps
      testMemberDepsMerged = {
        expr = builtins.hasAttr "workspace-package" (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).deps;
        expected = true;
      };
      
      # Test that existing deps still work
      testExistingDepsStillWork = {
        expr = builtins.hasAttr "default" (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).deps;
        expected = true;
      };
      
      # Test that all members have corresponding deps
      testAllMembersHaveDeps = {
        expr = builtins.all (member: builtins.hasAttr member (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).deps) (workspace.loadWorkspace { workspaceRoot = workspaces.workspace; }).members;
        expected = true;
      };
    };

  # Test workspace member edge cases
  loadWorkspace.memberEdgeCases =
    let
      testWorkspace = workspace.loadWorkspace { workspaceRoot = workspaces.workspace; };
    in
    {
      # Test member name extraction from various paths
      testMemberNameExtraction = {
        expr = testWorkspace.members;
        expected = [ "workspace-package" "workspace" ];
      };
      
      # Test that member info contains correct path
      testMemberPathCorrect = {
        expr = (testWorkspace.getMemberInfo "workspace-package").path;
        expected = "/packages/workspace-package";
      };
      
      # Test that root member has correct path
      testRootMemberPathCorrect = {
        expr = (testWorkspace.getMemberInfo "workspace").path;
        expected = "/";
      };
      
      # Test that member dependencies are correctly parsed
      testMemberDepsParsed = {
        expr = (testWorkspace.getMemberDeps "workspace-package").default;
        expected = [ "arpeggio" ];
      };
    };

  # Test workspace member integration with existing functionality
  loadWorkspace.memberIntegration =
    let
      testWorkspace = workspace.loadWorkspace { workspaceRoot = workspaces.workspace; };
    in
    {
      # Test that member deps are correctly structured
      testMemberDepsStructure = {
        expr = builtins.hasAttr "default" testWorkspace.deps."workspace-package";
        expected = true;
      };
      
      # Test that member info contains all required fields
      testMemberInfoStructure = {
        expr = builtins.all (field: builtins.hasAttr field (testWorkspace.getMemberInfo "workspace-package")) [ "name" "path" "version" "dependencies" "pyproject" ];
        expected = true;
      };
      
      # Test that all members are accessible via deps
      testAllMembersAccessible = {
        expr = builtins.all (member: builtins.hasAttr member testWorkspace.deps) testWorkspace.members;
        expected = true;
      };
    };
}
