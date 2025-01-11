{
  lib,
  pyproject-nix,
  lock1,
  overlays,
  workspace,
  ...
}:
let
  inherit (pyproject-nix.lib.scripts) loadScript;
  inherit (pyproject-nix.lib) pep508;
  inherit (lib)
    isPath
    isString
    hasContext
    importTOML
    isFunction
    listToAttrs
    nameValuePair
    mapAttrs
    groupBy
    concatMap
    filter
    ;

  mkSpec = dependencies: listToAttrs (map (dep: nameValuePair dep.name dep.extra) dependencies);

in

{

  /**
    Load a PEP-723 development script

    # Arguments

    `script`: Path to script

    `lockPath`: Alternative lock file path

    `config`: Config overrides for settings automatically inferred by `loadConfig`

      Can be passed as either:
      - An attribute set
      - A function taking the generated config as an argument, and returning the augmented config

    ## Script attributes
    - `name`: Base name of script as a string
    - `config`: Script config as loaded by `loadConfig`

    - `mkOverlay`: Create an overlay for usage with pyproject.nix's builders
    - `mkVirtualEnv`: Create an overlay for usage with pyproject.nix's builders
    - `renderScript`: Render script with shebang as a string
  */
  loadScript =
    {
      # Path to inline metadata script
      script,
      # Path to lock file for script
      lockPath ? script + ".lock",
      # Config overrides for settings automatically inferred by loadConfig
      # Can be passed as either:
      # - An attribute set
      # - A function taking the generated config as an argument, and returning the augmented config
      config ? { },
    }:
    # Scripts must either be passed as a path or as a contextful string
    assert (isPath script || (isString script && hasContext script));
    let
      uvLock = lock1.parseLock (importTOML lockPath);
      script' = loadScript { inherit script; };

      defaultSourcePreference =
        if config'.no-binary then
          "sdist"
        else if config'.no-build then
          "wheel"
        else
          throw "No sourcePreference was passed, and could not be automatically inferred from script";

      loadedConfig = workspace.loadConfig [ script'.metadata.metadata ];
      # Merge with overriden config
      config' = loadedConfig // (if isFunction config then config loadedConfig else config);

      localProjects = lock1.getLocalProjects {
        lock = uvLock;
        workspaceRoot = throw "Workspace root not set in scripts";
      };

    in
    {
      /*
        Basename of script as a string with .py suffix removed
        .
      */
      inherit (script') name;

      /*
        Script config as loaded by loadConfig
        .
      */
      config = config';

      /*
        Generate an overlay to use with pyproject.nix's build infrastructure.
        .
      */
      mkOverlay =
        {
          # Whether to prefer sources from either:
          # - wheel
          # - sdist
          sourcePreference ? defaultSourcePreference,
          environ ? { },
          workspaceRoot ? throw "No workspaceRoot provided",
        }:
        overlays.mkOverlay {
          inherit
            sourcePreference
            environ
            workspaceRoot
            localProjects
            ;
          lock = uvLock;
          config = config';
          spec = mkSpec script'.metadata.dependencies;
        };

      /*
        Make a virtual environment for script
        .
      */
      mkVirtualEnv =
        {
          pythonSet,
          environ ? { },
        }:
        let
          environ' = pep508.setEnviron (pep508.mkEnviron pythonSet.python) environ;
          spec = mapAttrs (_: concatMap (dep: dep.extras)) (
            groupBy (dep: dep.name) (
              filter (
                dep: dep.markers == null || pep508.evalMarkers environ' dep.markers
              ) script'.metadata.dependencies
            )
          );
        in
        pythonSet.mkVirtualEnv "${script'.name}-env" spec;

      /*
        Render script with shebang as a string
        .
      */
      renderScript = { venv }: "#!${venv}/bin/python\n" + script'.script;
    };

}
