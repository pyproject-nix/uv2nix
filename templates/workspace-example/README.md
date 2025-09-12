# Native UV Workspace Support Example

This example demonstrates the new native UV workspace support in uv2nix, showing how to work with individual workspace members and their dependencies.

## Features Demonstrated

### 1. Member Discovery
```nix
# Get list of workspace members
workspace.members  # ["webapp", "api", "shared"]

# List members programmatically
workspace.listMembers  # Same as above
```

### 2. Member-Specific Dependencies
```nix
# Access dependencies for specific members
workspace.deps."webapp".default    # Core dependencies
workspace.deps."webapp".optionals  # Optional dependencies
workspace.deps."webapp".groups     # Dependency groups
workspace.deps."webapp".all        # All dependencies

# Or use the helper function
workspace.getMemberDeps "webapp"   # Returns full dependency spec
```

### 3. Member Information
```nix
# Get detailed information about a member
let info = workspace.getMemberInfo "webapp";
in {
  name = info.name;           # "webapp"
  path = info.path;           # "/packages/webapp"
  version = info.version;     # "0.1.0"
  description = info.description;  # "Web application"
  dependencies = info.dependencies;  # Parsed dependencies
  pyproject = info.pyproject;  # Full pyproject.toml
}
```

## Use Cases

### Granular Container Images
Create minimal containers with only the dependencies needed for specific workspace members:

```nix
# Container with only web app dependencies
webapp-container = nixpkgs.dockerTools.buildImage {
  contents = [
    (pythonSet.mkVirtualEnv "webapp" 
      workspace.deps."webapp".default)
  ];
};
```

### Development Environments
Create different development shells for different parts of the workspace:

```nix
# Shell for web app development
webapp-shell = nixpkgs.mkShell {
  packages = [
    (pythonSet.mkVirtualEnv "webapp-dev" 
      workspace.deps."webapp".all)
  ];
};
```

### CI/CD Optimization
Run tests and builds only with the dependencies needed for specific tasks:

```nix
# Test job for specific member
test-webapp = nixpkgs.writeShellScriptBin "test-webapp" ''
  # Only install webapp dependencies
  python -m pip install ${lib.concatStringsSep " " workspace.deps."webapp".default}
  # Run tests
'';
```

## Benefits

1. **Reduced Container Size**: Build minimal containers with only necessary dependencies
2. **Faster CI/CD**: Install only what's needed for specific tasks
3. **Better Isolation**: Clear separation between different parts of the workspace
4. **Improved Performance**: Smaller environments load faster
5. **Native UV Integration**: Direct support for UV workspace concepts

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
```

### After (Native workspace support)
```nix
# Automatic dependency resolution from pyproject.toml
workspace.deps."generate-cpgs".default
# Returns: { boto3 = []; click = []; "fluidattacks-core" = [ "cpg" ]; platformdirs = []; }
```

## Running the Examples

```bash
# List workspace members
nix run .#list-members

# Show member information
nix run .#show-member-info

# Show member dependencies
nix run .#show-member-deps

# Enter development shell for specific member
nix develop .#webapp
nix develop .#api
nix develop .#shared

# Build container for specific member
nix build .#docker.webapp
nix build .#docker.api
```
