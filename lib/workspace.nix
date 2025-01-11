{
  lib,
  lock1,
  overlays,
  ...
}:

let
  inherit (lib)
    importTOML
    splitString
    length
    elemAt
    filter
    attrsToList
    match
    replaceStrings
    concatMap
    optional
    any
    fix
    mapAttrs
    attrNames
    unique
    foldl'
    isPath
    isAttrs
    attrValues
    assertMsg
    isFunction
    nameValuePair
    listToAttrs
    pathExists
    removePrefix
    groupBy
    head
    isString
    optionalString
    inPureEvalMode
    hasPrefix
    ;
  inherit (builtins) readDir hasContext;

  # Match str against a glob pattern
  globMatches =
    let
      mkRe = replaceStrings [ "*" ] [ ".*" ]; # Make regex from glob pattern
    in
    glob:
    let
      re = mkRe glob;
    in
    s: match re s != null;

  splitPath = splitString "/";

in

fix (self: {
  /**
    Load a workspace from a workspace root

    # Arguments

    `workspaceRoot`: Workspace root as a path

    `config`: Config overrides for settings automatically inferred by `loadConfig`

      Can be passed as either:
      - An attribute set
      - A function taking the generated config as an argument, and returning the augmented config

    ## Workspace attributes
    - `mkPyprojectOverlay`: Create an overlay for usage with pyproject.nix's builders
    - `mkPyprojectEditableOverlay`: Generate an overlay to use with pyproject.nix's build infrastructure to install dependencies in editable mode.
    - `config`: Workspace config as loaded by `loadConfig`
    - `deps`: Pre-defined dependency declarations for top-level workspace packages
      - `default`: No optional-dependencies or dependency-groups enabled
      - `optionals`: All optional-dependencies enabled
      - `groups`: All dependency-groups enabled
      - `all`: All optional-dependencies & dependency-groups enabled
  */
  loadWorkspace =
    {
      # Workspace root as a path
      workspaceRoot,
      # Config overrides for settings automatically inferred by loadConfig
      # Can be passed as either:
      # - An attribute set
      # - A function taking the generated config as an argument, and returning the augmented config
      config ? { },
    }:
    assert (isPath workspaceRoot || (isString workspaceRoot || hasContext workspaceRoot));
    assert isAttrs config || isFunction config;
    let
      pyproject = importTOML (workspaceRoot + "/pyproject.toml");
      uvLock = lock1.parseLock (importTOML (workspaceRoot + "/uv.lock"));

      localPackages = filter lock1.isLocalPackage uvLock.package;

      workspaceProjects = lock1.getLocalProjects {
        lock = uvLock;
        inherit localPackages workspaceRoot;
      };

      # Load supported tool.uv settings
      loadedConfig = self.loadConfig (
        # Extract pyproject.toml from loaded projects
        (map (project: project.pyproject) (attrValues workspaceProjects))
        # If workspace root is a virtual root it wasn't discovered as a member directory
        # but config should also be loaded from a virtual root
        ++ optional (!(pyproject ? project)) pyproject
      );

      # Merge with overriden config
      config' = loadedConfig // (if isFunction config then config loadedConfig else config);

      # Set default sourcePreference
      defaultSourcePreference =
        if config'.no-binary then
          "sdist"
        else if config'.no-build then
          "wheel"
        else
          throw "No sourcePreference was passed, and could not be automatically inferred from workspace config";

    in
    assert assertMsg (
      !(config'.no-binary && config'.no-build)
    ) "Both tool.uv.no-build and tool.uv.no-binary are set to true, making the workspace unbuildable";
    rec {
      /*
        Workspace config as loaded by loadConfig
        .
      */
      config = config';

      /*
        Generate an overlay to use with pyproject.nix's build infrastructure.

        See https://pyproject-nix.github.io/pyproject.nix/lib/build.html
      */
      mkPyprojectOverlay =
        {
          # Whether to prefer sources from either:
          # - wheel
          # - sdist
          #
          # See FAQ for more information.
          sourcePreference ? defaultSourcePreference,
          # PEP-508 environment customisations.
          # Example: { platform_release = "5.10.65"; }
          environ ? { },
          # Dependency specification used for conflict resolution.
          # By default mkPyprojectOverlay resolves the entire workspace, but that will not work for resolutions with conflicts.
          dependencies ? deps.all,
        }:
        overlays.mkOverlay {
          inherit sourcePreference environ workspaceRoot;
          localProjects = workspaceProjects;
          spec = dependencies;
          lock = uvLock;
          config = config';
        };

      /*
        Generate an overlay to use with pyproject.nix's build infrastructure to install dependencies in editable mode.
        Note: Editable support is still under development and this API might change.

        See https://pyproject-nix.github.io/pyproject.nix/lib/build.html
      */
      mkEditablePyprojectOverlay =
        {
          # Editable root as a string.
          root ? (toString workspaceRoot),
          # Workspace members to make editable as a list of strings. Defaults to all local projects.
          members ? map (package: package.name) localPackages,
        }:
        assert assertMsg (!hasPrefix builtins.storeDir root) ''
          Editable root was passed as a Nix store path.

          ${optionalString inPureEvalMode ''
            This is most likely because you are using Flakes, and are automatically inferring the editable root from workspaceRoot.
            Flakes are copied to the Nix store on evaluation. This can temporarily be worked around using --impure.
          ''}
          Pass editable root either as a string pointing to an absolute non-store path, or use environment variables for relative paths.
        '';
        _final: prev:
        let
          # Filter any local packages that might be deactivated by markers or other filtration mechanisms.
          activeMembers = filter (name: !prev ? name) members;
        in
        listToAttrs (
          map (
            name:
            nameValuePair name (
              prev.${name}.override {
                # Prefer src layout if available
                editableRoot =
                  let
                    inherit (workspaceProjects.${name}) projectRoot;
                  in
                  root
                  + (removePrefix (toString workspaceRoot) (
                    toString (if pathExists (projectRoot + "/src") then (projectRoot + "/src") else projectRoot)
                  ));
              }
            )
          ) activeMembers
        );

      # Pre-defined dependency specifications.
      deps =
        let
          # Extract dependency groups/optional-dependencies from all local projects
          # operating under the assumptions that a local project only has one possible resolution
          # and that no local projects are filtered out by markers
          packages' =
            mapAttrs
              (
                _name: packages:
                assert length packages == 1;
                head packages
              )
              (
                groupBy (package: package.name)
                  # Don't include local packages pulled in to the workspace from a directory specification.
                  # These might be local, but are not considered as a part of the workspace
                  (filter (package: !package.source ? directory) localPackages)
              );
        in
        {
          # Dependency specification with all optional dependencies & groups
          all = mapAttrs (
            _: package: unique (attrNames package.optional-dependencies ++ attrNames package.dev-dependencies)
          ) packages';

          # Dependency specifications with will all optional dependencies
          optionals = mapAttrs (_: package: attrNames package.optional-dependencies) packages';

          # Dependency specifications with will all groups
          groups = mapAttrs (_: package: attrNames package.dev-dependencies) packages';

          # Dependency specification with default dependencies
          default = mapAttrs (
            name: _: workspaceProjects.${name}.pyproject.tool.uv.default-groups or [ ]
          ) packages';
        };
    };

  /**
    Load supported configuration from workspace

    Supports:
    - tool.uv.no-binary
    - tool.uv.no-build
    - tool.uv.no-binary-packages
    - tool.uv.no-build-packages
  */
  loadConfig =
    # List of imported (lib.importTOML) pyproject.toml files from workspace from which to load config
    pyprojects:
    let
      no-build' = foldl' (
        acc: pyproject:
        (
          if pyproject ? tool.uv.no-build then
            (
              if acc != null && pyproject.tool.uv.no-build != acc then
                (throw "Got conflicting values for tool.uv.no-build")
              else
                pyproject.tool.uv.no-build
            )
          else
            acc
        )
      ) null pyprojects;

      no-binary' = foldl' (
        acc: pyproject:
        (
          if pyproject ? tool.uv.no-binary then
            (
              if acc != null && pyproject.tool.uv.no-binary != acc then
                (throw "Got conflicting values for tool.uv.no-binary")
              else
                pyproject.tool.uv.no-binary
            )
          else
            acc
        )
      ) null pyprojects;
    in
    {
      no-build = if no-build' != null then no-build' else false;
      no-binary = if no-binary' != null then no-binary' else false;
      no-binary-package = unique (
        concatMap (pyproject: pyproject.tool.uv.no-binary-package or [ ]) pyprojects
      );
      no-build-package = unique (
        concatMap (pyproject: pyproject.tool.uv.no-build-package or [ ]) pyprojects
      );
    };

  /*
    Discover workspace member directories from a workspace root.
    Returns a list of strings relative to the workspace root.
  */
  discoverWorkspace =
    {
      # Workspace root directory
      workspaceRoot,
      # Workspace top-level pyproject.toml
      pyproject ? importTOML (workspaceRoot + "/pyproject.toml"),
    }:
    let
      workspace' = pyproject.tool.uv.workspace or { };
      excluded = map (g: globMatches "/${g}") (workspace'.exclude or [ ]);
      globs = map splitPath (workspace'.members or [ ]);

    in
    # Get a list of workspace member directories
    filter (x: length excluded == 0 || any (e: !e x) excluded) (
      concatMap (
        glob:
        let
          max = (length glob) - 1;
          recurse =
            rel: i:
            let
              dir = workspaceRoot + "/${rel}";
              dirs = map (e: e.name) (filter (e: e.value == "directory") (attrsToList (readDir dir)));
              matches = filter (globMatches (elemAt glob i)) dirs;
            in
            if i == max then
              map (child: rel + "/${child}") matches
            else
              concatMap (child: recurse (rel + "/${child}") (i + 1)) matches;
        in
        recurse "" 0
      ) globs
    )
    # If the package is a virtual root we don't add the workspace root to project discovery
    ++ optional (pyproject ? project) "/";

})
