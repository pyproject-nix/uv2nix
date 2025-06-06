{
  lib,
  pkgs,
  package-name,
  pythonSet,
  self,
  pyproject-nix,
  pyproject-build-systems,
  uv2nix,

  ...
}:
let

  asgiApp = "django_webapp.asgi:application";
  settingsModules = {
    prod = "django_webapp.settings";
  };

  workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = "${self}"; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
  };

  editableOverlay = workspace.mkEditablePyprojectOverlay {
    root = "$REPO_ROOT";
  };

  # Python sets grouped per system
  envs = lib.attrsets.genAttrs workspace.deps.all.${package-name} (
    name: pythonSet.mkVirtualEnv "${package-name}-${name}-env" { ${package-name} = [ name ]; }
  );
in
(pythonSet.mkVirtualEnv "${package-name}-env" workspace.deps.default).overrideAttrs (
  self: super: {
    passthru = envs;
  }
)
