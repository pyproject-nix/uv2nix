# Working with UV Workspace Members

uv2nix now provides native support for UV workspaces, allowing you to work with individual workspace members and their dependencies directly from Nix.

> **Reference**: [UV Workspaces Documentation](https://docs.astral.sh/uv/concepts/projects/workspaces/#getting-started)

## Overview

UV workspaces organize large codebases by splitting them into multiple packages with common dependencies. With uv2nix's native workspace support, you can:

- Access individual workspace member dependencies
- Create granular environments for specific members
- Build minimal containers with only necessary dependencies
- Optimize CI/CD by installing only what's needed

## Basic Usage

### Loading a Workspace

```nix
let
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { 
    workspaceRoot = ./.; 
  };
in
# Use workspace...
```

### Accessing Workspace Members

```nix
# List all workspace members
workspace.members  # ["webapp", "api", "shared"]

# Get member information
let info = workspace.getMemberInfo "webapp";
in {
  name = info.name;           # "webapp"
  path = info.path;           # "/packages/webapp"
  version = info.version;     # "0.1.0"
  description = info.description;
  dependencies = info.dependencies;
}
```

### Member-Specific Dependencies

```nix
# Access dependencies for a specific member
workspace.deps."webapp".default    # Core dependencies
workspace.deps."webapp".optionals  # Optional dependencies  
workspace.deps."webapp".groups     # Dependency groups
workspace.deps."webapp".all        # All dependencies

# Or use the helper function
workspace.getMemberDeps "webapp"   # Returns full dependency spec
```

## Use Cases

### 1. Granular Container Images

Create minimal containers with only the dependencies needed for specific workspace members:

```nix
let
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  pythonSet = pkgs.callPackage pyproject-nix.build.packages {
    python = pkgs.python312;
  };
in
{
  # Container with only web app dependencies
  webapp-container = pkgs.dockerTools.buildImage {
    name = "myapp-webapp";
    contents = [
      (pythonSet.mkVirtualEnv "webapp" 
        workspace.deps."webapp".default)
    ];
    config.Cmd = [ "python" "-m" "webapp.main" ];
  };

  # API-only container
  api-container = pkgs.dockerTools.buildImage {
    name = "myapp-api";
    contents = [
      (pythonSet.mkVirtualEnv "api" 
        workspace.deps."api".default)
    ];
    config.Cmd = [ "python" "-m" "api.main" ];
  };
}
```

### 2. Development Environments

Create different development shells for different parts of the workspace:

```nix
{
  devShells = {
    # Shell for web app development
    webapp = pkgs.mkShell {
      packages = [
        (pythonSet.mkVirtualEnv "webapp-dev" 
          workspace.deps."webapp".all)
        pkgs.nodejs
        pkgs.yarn
      ];
    };

    # Shell for API development
    api = pkgs.mkShell {
      packages = [
        (pythonSet.mkVirtualEnv "api-dev" 
          workspace.deps."api".all)
        pkgs.postgresql
        pkgs.redis
      ];
    };

    # Shell for shared library development
    shared = pkgs.mkShell {
      packages = [
        (pythonSet.mkVirtualEnv "shared-dev" 
          workspace.deps."shared".all)
      ];
    };
  };
}
```

### 3. CI/CD Optimization

Run tests and builds only with the dependencies needed for specific tasks:

```nix
{
  packages.ci = {
    # Test job for web app
    test-webapp = pkgs.writeShellScriptBin "test-webapp" ''
      set -e
      echo "Testing webapp with dependencies: ${lib.concatStringsSep ", " workspace.deps."webapp".default}"
      # Install only webapp dependencies
      python -m pip install ${lib.concatStringsSep " " workspace.deps."webapp".default}
      # Run webapp tests
    '';

    # Test job for API
    test-api = pkgs.writeShellScriptBin "test-api" ''
      set -e
      echo "Testing API with dependencies: ${lib.concatStringsSep ", " workspace.deps."api".default}"
      # Install only API dependencies
      python -m pip install ${lib.concatStringsSep " " workspace.deps."api".default}
      # Run API tests
    '';

    # Lint job for shared library
    lint-shared = pkgs.writeShellScriptBin "lint-shared" ''
      set -e
      echo "Linting shared library with dependencies: ${lib.concatStringsSep ", " workspace.deps."shared".default}"
      # Install only shared dependencies
      python -m pip install ${lib.concatStringsSep " " workspace.deps."shared".default}
      # Run linting
    '';
  };
}
```

### 4. Environment-Specific Packages

Create different package sets for different environments:

```nix
{
  packages = {
    # Production web app with minimal dependencies
    webapp-prod = pythonSet.mkVirtualEnv "webapp-prod" 
      workspace.deps."webapp".default;

    # Development web app with all dependencies
    webapp-dev = pythonSet.mkVirtualEnv "webapp-dev" 
      workspace.deps."webapp".all;

    # Testing environment with test dependencies
    webapp-test = pythonSet.mkVirtualEnv "webapp-test" 
      (workspace.deps."webapp".all ++ [ "pytest" "pytest-asyncio" ]);
  };
}
```

## API Reference

### Workspace Object

The workspace object returned by `loadWorkspace` includes:

- `members`: List of workspace member names
- `deps`: Dependency specifications
  - `default`: Workspace-wide default dependencies
  - `optionals`: Workspace-wide optional dependencies
  - `groups`: Workspace-wide dependency groups
  - `all`: All workspace-wide dependencies
  - `"member-name"`: Member-specific dependency specifications
- `getMemberDeps(memberName)`: Get dependency specifications for a specific member
- `getMemberInfo(memberName)`: Get detailed information about a workspace member
- `listMembers`: List all workspace member names

### Member Dependency Specifications

Each member's dependency specification includes:

- `default`: Core dependencies from `project.dependencies`
- `optionals`: Optional dependencies from `project.optional-dependencies`
- `groups`: Dependency groups from `project.dependency-groups`
- `all`: All optional dependencies and groups combined

### Member Information

The `getMemberInfo` function returns:

- `name`: Member name
- `path`: Path relative to workspace root
- `version`: Version from pyproject.toml
- `description`: Description from pyproject.toml
- `dependencies`: Parsed dependencies object
- `pyproject`: Full parsed pyproject.toml

## Migration from Manual Workarounds

### Before (Manual dependency management)

```nix
# Had to manually maintain dependency specs
generateCpgsSpec = {
  boto3 = [ ];
  click = [ ];
  "fluidattacks-core" = [ "cpg" ];
  platformdirs = [ ];
};

# Manual environment creation
webappEnv = pythonSet.mkVirtualEnv "webapp" generateCpgsSpec;
```

### After (Native workspace support)

```nix
# Automatic dependency resolution from pyproject.toml
workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

# Direct access to member dependencies
webappEnv = pythonSet.mkVirtualEnv "webapp" 
  workspace.deps."webapp".default;
```

## Benefits

1. **Reduced Maintenance**: No manual dependency synchronization
2. **Better Performance**: Smaller, more targeted environments
3. **Improved Developer Experience**: Intuitive API that matches UV concepts
4. **CI/CD Optimization**: Build only what's needed for specific tasks
5. **Native UV Integration**: Direct support for UV workspace features

## Best Practices

1. **Use Member-Specific Dependencies**: Prefer `workspace.deps."member".default` over `workspace.deps.default` for member-specific tasks
2. **Leverage Granular Environments**: Create separate environments for different parts of your workspace
3. **Optimize Container Images**: Build minimal containers with only necessary dependencies
4. **Use Helper Functions**: Leverage `getMemberDeps` and `getMemberInfo` for dynamic member handling
5. **Document Member Dependencies**: Use the member information to generate documentation or validation scripts
