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
    concatStringsSep
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
    groupBy
    head
    isString
    optionalString
    inPureEvalMode
    hasPrefix
    path
    replicate
    drop
    hasAttr
    getAttr
    ;
  inherit (lib.lists) commonPrefix;
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

  getSubComponents = p: path.subpath.components (path.splitRoot p).subpath;

  # Extract workspace member dependencies from uv.lock
  # This is more reliable than parsing pyproject.toml files
  extractMemberDependenciesFromLock = uvLock:
    let
      # Find all workspace packages (those with editable source)
      workspacePackages = builtins.filter (pkg: 
        pkg.source ? editable
      ) uvLock.package;
      
      # Create a mapping from package name to dependencies
      packageDeps = builtins.listToAttrs (
        map (pkg: {
          name = pkg.name;
          value = {
            # Convert dependencies to the format expected by mkVirtualEnv
            # { "package-name" = [ "extra1" "extra2" ]; }
            dependencies = builtins.listToAttrs (
              map (dep: {
                name = dep.name;
                value = if dep ? extra then dep.extra else [];
              }) (if pkg ? dependencies then pkg.dependencies else [])
            );
            # Extract optional dependencies and groups from metadata if available
            optional-dependencies = {};
            dev-dependencies = {};
            # Store package metadata from uv.lock
            package-info = {
              name = pkg.name;
              version = if pkg ? version then pkg.version else "0.0.0";
              source = pkg.source;
            };
          };
        }) workspacePackages
      );
    in
    packageDeps;

  # Get workspace member names from uv.lock (more reliable than directory names)
  getMemberNamesFromLock = uvLock:
    let
      # Find all workspace packages (those with editable source)
      workspacePackages = builtins.filter (pkg: 
        pkg.source ? editable
      ) uvLock.package;
    in
    map (pkg: pkg.name) workspacePackages;

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
    - `mkEditablePyprojectOverlay`: Generate an overlay to use with pyproject.nix's build infrastructure to install dependencies in editable mode.
    - `config`: Workspace config as loaded by `loadConfig`
    - `members`: List of workspace member names
    - `deps`: Pre-defined dependency declarations for workspace packages
      - `default`: No optional-dependencies or dependency-groups enabled (workspace-wide)
      - `optionals`: All optional-dependencies enabled (workspace-wide)
      - `groups`: All dependency-groups enabled (workspace-wide)
      - `all`: All optional-dependencies & dependency-groups enabled (workspace-wide)
      - `"member-name"`: Member-specific dependency specifications
        - `default`: Member's core dependencies
        - `optionals`: Member's optional dependencies
        - `groups`: Member's dependency groups
        - `all`: All member dependencies and groups
    - `getMemberDeps`: Get dependency specifications for a specific member
    - `getMemberInfo`: Get detailed information about a workspace member
    - `listMembers`: List all workspace member names
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
    assert (
      isPath workspaceRoot
      || (isString workspaceRoot && hasContext workspaceRoot)
      || (isAttrs workspaceRoot && workspaceRoot ? outPath)
    );
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
    let
      # Get member names from uv.lock (more reliable than directory discovery)
      memberNames = getMemberNamesFromLock uvLock;
      
      # Extract member dependencies from uv.lock (more reliable than pyproject.toml)
      memberDependenciesFromLock = extractMemberDependenciesFromLock uvLock;
      
      # Create dependency specifications for each member
      memberDepsData = mapAttrs (name: deps:
        {
          # Default dependencies - convert from uv.lock format to list format for compatibility
          default = attrNames deps.dependencies;
          # All optional dependencies
          optionals = attrNames deps.optional-dependencies;
          # All dependency groups
          groups = attrNames deps.dev-dependencies;
          # All optional dependencies and groups
          all = unique (attrNames deps.optional-dependencies ++ attrNames deps.dev-dependencies);
        }
      ) memberDependenciesFromLock;
      
    in
    rec {
      /*
        Workspace config as loaded by loadConfig
        .
      */
      config = config';

      /*
        List of workspace member names
        .
      */
      members = memberNames;

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
                editableRoot =
                  let
                    inherit (workspaceProjects.${name}) projectRoot;
                    # Split projectRoot/workspaceRoot into subcomponents to support editable projects in parent directories.
                    prSub = getSubComponents projectRoot;
                    wrSub = getSubComponents workspaceRoot;
                    n = length (commonPrefix prSub wrSub);
                  in
                  concatStringsSep "/" ([ root ] ++ replicate ((length wrSub) - n) ".." ++ drop n prSub);
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

      /*
        Get dependencies for a specific workspace member
        
        # Arguments
        
        `memberName`: Name of the workspace member (package name from uv.lock)
      */
      getMemberDeps = memberName: 
        if hasAttr memberName memberDepsData then
          memberDepsData.${memberName}
        else
          throw "Workspace member '${memberName}' not found. Available members: ${concatStringsSep ", " memberNames}";

      /*
        Get detailed information about a workspace member
        
        # Arguments
        
        `memberName`: Name of the workspace member (package name from uv.lock)
      */
      getMemberInfo = memberName:
        if hasAttr memberName memberDependenciesFromLock then
          let
            memberData = memberDependenciesFromLock.${memberName};
            packageInfo = memberData.package-info;
          in
          {
            name = memberName;
            version = packageInfo.version;
            source = packageInfo.source;
            path = if packageInfo.source ? editable then packageInfo.source.editable else "";
            dependencies = attrNames memberData.dependencies;
            optional-dependencies = memberData.optional-dependencies;
            dev-dependencies = memberData.dev-dependencies;
          }
        else
          throw "Workspace member '${memberName}' not found. Available members: ${concatStringsSep ", " memberNames}";

      /*
        Workspace member dependencies
      */
      memberDeps = memberDepsData;

      /*
        List all workspace member names
      */
      listMembers = memberNames;
    };

  /**
    Load supported configuration from workspace

    Supports:
    - tool.uv.no-binary
    - tool.uv.no-build
    - tool.uv.no-binary-package
    - tool.uv.no-build-package
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
