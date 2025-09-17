{ pyproject-nix, lib, ... }:

let
  inherit (pyproject-nix.lib.project) loadUVPyproject;
  inherit (pyproject-nix.lib.pep508) parseMarkers evalMarkers;
  inherit (pyproject-nix.lib.pypa) parseWheelFileName;
  inherit (pyproject-nix.lib) pep440;
  inherit (builtins)
    baseNameOf
    toJSON
    partition
    readDir
    ;
  inherit (lib)
    mapAttrs
    fix
    filter
    length
    all
    groupBy
    concatMap
    attrValues
    concatLists
    genericClosure
    isAttrs
    isList
    attrNames
    typeOf
    elem
    head
    listToAttrs
    any
    optionalAttrs
    throwIf
    filterAttrs
    nameValuePair
    pathExists
    unique
    assertMsg
    ;

in

fix (self: {

  /*
    Resolve dependencies from uv.lock
    .
  */
  resolveDependencies =
    {
      # Lock file as parsed by parseLock
      lock,
      # PEP-508 environment as returned by pyproject-nix.lib.pep508.mkEnviron
      environ,
      # List of dependency names to start resolution from
      dependencies,
    }:
    # Assert that there are no conflicts, or that conflicts have been filtered
    assert lock.conflicts == [ ];
    let
      # Evaluate top-level resolution-markers
      resolution-markers = mapAttrs (_: evalMarkers environ) lock.resolution-markers;

      # Filter dependencies of packages
      packages = map (self.filterPackage environ) (
        # Filter packages based on resolution-markers
        filter (
          pkg:
          length pkg.resolution-markers == 0
          || any (
            markers:
            resolution-markers.${markers} or (
              # Uv has a bug introduced in https://github.com/astral-sh/uv/pull/11513
              # Where internal conflict markers aren't correctly stripped.
              #
              # This makes it impossible to correctly consume a lock with conflict markers.
              # I'm hoping that this will eventually get fixed, but in the mean time this means that:
              # 1. We can only really evaluate conflict markers on a best effort basis.
              # 2. Degraded performance because we can no longer rely on the top-level markers as a cache lookup.
              evalMarkers environ (parseMarkers markers)
            )
          ) pkg.resolution-markers
        ) lock.package
      );

      # Group list of package candidates by package name (pname)
      candidates = groupBy (pkg: pkg.name) packages;

      # Group list of package candidates by qualified package name (pname + version)
      allCandidates = groupBy (pkg: "${pkg.name}-${pkg.version}") packages;

      # Make key return for genericClosure
      mkKey = package: {
        key = "${package.name}-${package.version}";
        inherit package;
      };

      # Resolve dependencies recursively
      allDependencies = groupBy (dep: dep.package.name) (genericClosure {
        # Recurse into top-level dependencies.
        startSet = concatMap (name: map mkKey candidates.${name}) dependencies;

        operator =
          { key, ... }:
          # Note: Markers are already filtered.
          # Consider: Is it more efficient to only do marker filtration at resolve time, no pre-filtering?
          concatMap (
            candidate:
            map mkKey (
              concatMap
                (
                  dep: filter (package: dep.version == null || dep.version == package.version) candidates.${dep.name}
                )
                (
                  candidate.dependencies
                  ++ (concatLists (attrValues candidate.optional-dependencies))
                  ++ (concatLists (attrValues candidate.dev-dependencies))
                )
            )
          ) allCandidates.${key};
      });

      depNames = attrNames allDependencies;

      # Reduce dependency candidates down to the one resolved dependency.
      reduceDependencies =
        i: attrs:
        if i >= 100 then
          throw "Infinite recursion: Could not resolve dependencies."
        else
          let
            result = mapAttrs (
              name: candidates:
              if isAttrs candidates then
                candidates # Already reduced
              else if length candidates == 1 then
                (head candidates).package
              # Ambigious, filter further
              else
                let
                  filterDeps' =
                    package:
                    let
                      filtered' = filter (x: x.name == name) package.dependencies;
                    in
                    if length filtered' > 1 then
                      (throw ''
                        Non disjoint install time resolution for package '${name}' depending on multiple versions of '${package.name}'.

                        You are most likely using an older version of uv to produce uv.lock which contains marker bugs.
                        Re-lock with a later version of uv and try again.
                      '')
                    else
                      filtered';

                  # Get version declarations for this package from all other packages to use as a filter
                  versions' = concatMap (
                    n:
                    let
                      package = attrs.${n};
                      versions =
                        if isList package then
                          map (pkg: pkg.version) (concatMap (pkg: filterDeps' pkg.package) package)
                        else if isAttrs package then
                          map (pkg: pkg.version) (filterDeps' package)
                        else
                          throw "Unhandled type: ${typeOf package}";
                    in
                    if versions != [ ] then [ versions ] else [ ]
                  ) depNames;

                  filtered =
                    if length versions' > 0 then
                      filter (candidate: all (versions: elem candidate.package.version versions) versions') candidates
                    else
                      candidates;
                in
                filtered
            ) attrs;
            done = all isAttrs (attrValues result);
          in
          if done then result else reduceDependencies (i + 1) result;

    in
    reduceDependencies 0 allDependencies;

  /*
    Check if a package is a local package.
    .
  */
  isLocalPackage =
    package:
    # Path to local workspace project
    package.source ? editable
    # Path to non-uv project
    || package.source ? directory
    # Path to local project with no build-system defined
    || package.source ? virtual;

  /*
    Get relative path for a local package
    .
  */
  getLocalPath =
    package:
    package.source.editable or package.source.directory or package.source.virtual
      or (throw "Not a project path: ${toJSON package.source}");

  /*
    Filter dependencies/optional-dependencies/dev-dependencies from a uv.lock package entry
    .
  */
  filterPackage =
    environ:
    let
      filterDeps = filter (dep: dep.marker == null || evalMarkers environ dep.marker);
    in
    package:
    package
    // {
      dependencies = filterDeps package.dependencies;
      optional-dependencies = mapAttrs (_: filterDeps) package.optional-dependencies;
      dev-dependencies = mapAttrs (_: filterDeps) package.dev-dependencies;
    };

  /*
    Filter package conflicts from lock according to dependency specification.

    This function exists to filter uv.lock _before_ being passed to resolveDependencies,
    allowing the runtime solver to treat the lock as if no conflicts exists.
  */
  filterConflicts =
    {
      lock,
      spec,
    }:
    let
      # Get a list of deselected dependency conflicts to filter
      extras' = pkg:
        spec.${pkg} or (throw "Package '${spec.package}' not present in resolution specification");
      conflictEntryRelevant = def: elem (def.extra or def.group) (extras' def.package);
      # Every element is a uv conflict declaration parsed into two lists:
      # all items which apply to this spec, and all which don’t.
      #
      # [
      #   { right = [ <me> ]; wrong = [ <not me> <not me 2> ... ]; }
      #   ...
      # ]
      conflictsRes = map (partition conflictEntryRelevant) lock.conflicts;
      # Any conflict declaration in which there is not a _single_
      # declaration which is relevant to this specification is completely
      # irrelevant, and we should just ignore it wholesale.  All the rest
      # can be merged into a single declaration.
      conflictMerged = lib.mapAttrs (_: lib.unique)
        (lib.zipAttrsWith (_: lib.flatten)
          (builtins.filter (c: let
            matches = builtins.length c.right;
          in
            throwIf
              (matches > 1)
              "Conflict resolution selected more than one conflict specifier, resolution still ambigious: ${lib.concatMapStringsSep ", " builtins.toJSON c.right}"
              matches == 1
          ) conflictsRes));
      deselected' = conflictMerged.wrong or [];
      deselected = groupBy (def: def.package) deselected';
    in
    lock
    // {
      conflicts = [ ];
      package = map (
        pkg:
        if !deselected ? ${pkg.name} then
          pkg
        else
          pkg
          // {
            optional-dependencies = filterAttrs (
              n: _: !any (def: def ? extra && def.extra == n) deselected.${pkg.name}
            ) pkg.optional-dependencies;
            dev-dependencies = filterAttrs (
              n: _: !any (def: def ? group && def.group == n) deselected.${pkg.name}
            ) pkg.dev-dependencies;
          }
      ) lock.package;
    };

  /*
    Parse unmarshaled uv.lock
    .
  */
  parseLock =
    let
      parseOptions =
        {
          resolution-mode ? null,
          exclude-newer ? null,
          prerelease-mode ? null,
        }:
        {
          inherit resolution-mode exclude-newer prerelease-mode;
        };
    in
    {
      version,
      requires-python,
      manifest ? { },
      package ? [ ],
      resolution-markers ? [ ],
      supported-markers ? [ ],
      required-markers ? [ ],
      options ? { },
      conflicts ? [ ],
      revision ? 0,
    }:
    assert version == 1;
    let
      # Aggregate all lists of top level markers into a single top-level marker attrset
      #
      # This is so that we only have to parse a marker exactly once even if the marker is repeated
      # across marker lists.
      topLevelMarkers = listToAttrs (
        map (markers: nameValuePair markers (parseMarkers markers)) (
          unique (resolution-markers ++ supported-markers ++ required-markers)
        )
      );
      filterMarkers = list: filterAttrs (markers: _: elem markers list) topLevelMarkers;

    in
    {
      inherit version conflicts;
      requires-python = pep440.parseVersionConds requires-python;
      manifest = self.parseManifest manifest;
      package = map (self.parsePackage topLevelMarkers) package;
      resolution-markers = filterMarkers resolution-markers;
      supported-markers = filterMarkers supported-markers;
      required-markers = filterMarkers required-markers;
      options = parseOptions options;
      inherit revision;
    };

  parseManifest =
    {
      members ? [ ],
    }:
    {
      inherit members;
    };

  /*
    Parse a package entry from uv.lock
    .
  */
  parsePackage =
    let
      parseWheel =
        {
          url ? null,
          filename ? null,
          path ? null,
          hash ? null,
          size ? null,
          ...
        }@whl:
        # Assert mutually exclusive args
        assert (whl ? url) -> (!whl ? filename && !whl ? path);
        assert (whl ? filename) -> (!whl ? url && !whl ? path);
        assert (whl ? path) -> (!whl ? url && !whl ? filename);
        {
          inherit size;
        }
        // optionalAttrs (url != null) {
          inherit url;
          file' = parseWheelFileName (baseNameOf url);
        }
        // optionalAttrs (filename != null) {
          inherit filename;
          file' = parseWheelFileName filename;
        }
        // optionalAttrs (path != null) {
          inherit path;
          file' = parseWheelFileName (baseNameOf path);
        }
        // optionalAttrs (whl ? hash) {
          inherit hash;
        };

      parseMetadata =
        let
          parseRequires =
            {
              name,
              marker ? null,
              url ? null,
              path ? null,
              directory ? null,
              editable ? null,
              git ? null,
              specifier ? null,
              extras ? null,
              ...
            }:
            {
              inherit
                name
                url
                path
                directory
                editable
                git
                extras
                ;
              marker = if marker != null then parseMarkers marker else null;
              specifier = if specifier != null then pep440.parseVersionConds specifier else null;
            };
        in
        {
          requires-dist ? [ ],
          requires-dev ? { },
          provides-extras ? [ ],
        }:
        {
          requires-dist = map parseRequires requires-dist;
          requires-dev = mapAttrs (_: map parseRequires) requires-dev;
          inherit provides-extras;
        };

    in
    topLevelMarkers:
    let
      # Parse marker, but avoid parsing markers already present in toplevel uv.lock marker fields
      parseMarker = marker: topLevelMarkers.${marker} or (parseMarkers marker);
      inherit (pep440) parseVersion;

      parseDependency =
        {
          name,
          marker ? null,
          version ? null,
          source ? { },
          extra ? [ ],
        }:
        {
          inherit
            name
            source
            version
            extra
            ;
          version' = if version != null then parseVersion version else null;
          marker = if marker != null then parseMarker marker else null;
        };

    in
    {
      name,
      source,
      # Uv doesn't put the version in the lock if it's dynamic
      # Use a dummy version instead.
      version ? "0.0.0",
      resolution-markers ? [ ],
      dependencies ? [ ],
      optional-dependencies ? { },
      dev-dependencies ? { },
      metadata ? { },
      wheels ? [ ],
      sdist ? { },
    }:
    assert assertMsg (name != "python")
      "A package from uv.lock is called `python` which is a reserved name for the interpreter derivation";
    assert assertMsg (
      name != "pkgs"
    ) "A package from uv.lock is called `pkgs` which is a reserved name for the nixpkgs package set";
    {
      inherit
        name
        version
        source
        sdist
        ;
      version' = pep440.parseVersion version;
      wheels = map parseWheel wheels;
      metadata = parseMetadata metadata;
      # Don't parse resolution-markers.
      # All resolution-markers are also in the toplevel, meaning the string can be used as a lookup key from the top-level marker.
      inherit resolution-markers;
      dependencies = map parseDependency dependencies;

      optional-dependencies = mapAttrs (_: map parseDependency) optional-dependencies;
      dev-dependencies = mapAttrs (_: map parseDependency) dev-dependencies;
    };

  getLocalProjects =
    # Get local packages from lock as an attribute set of pyproject.nix projects.
    {
      lock,
      workspaceRoot,
      localPackages ? filter self.isLocalPackage lock.package,
    }:
    listToAttrs (
      map (
        package:
        let
          localPath = self.getLocalPath package;
          projectRoot = if localPath == "." then workspaceRoot else workspaceRoot + "/${localPath}";
        in
        nameValuePair package.name (
          if (pathExists (projectRoot + "/pyproject.toml")) then
            (loadUVPyproject {
              inherit projectRoot;
            })
          else
            # When using submodules with Flakes users need to pass submodules=1 to `nix develop`.
            # If this is _not_ passed users will end up with an empty directory instead, which triggers
            # accessing the tainted attributes below.
            throwIf (pathExists projectRoot && readDir projectRoot == { })
              ''
                Project root for package '${package.name}' is empty.

                This can happen when using Git submodules within a Flake without passing submodules=1 to `nix develop`.
              ''
              # Return an empty dummy project for projects that have no pyproject.toml in the root.
              {
                dependencies = rec {
                  # Return empty list of build-systems to trigger legacy fallback lookup.
                  build-systems = [ ];
                  # None of these fields should be accessed because dependencies are taken from uv.lock.
                  # Taint them to ensure we don't accidentally rely on them.
                  dependencies = throw ''
                    internal error: accessed dependencies from pyproject.nix project, not uv.lock

                    Hint: Are you in a Flake and forgot to `git add pyproject.toml`?
                  '';
                  extras = dependencies;
                  groups = dependencies;

                };
                pyproject = { }; # The unmarshaled contents of pyproject.toml
                inherit projectRoot; # Path to project root
                requires-python = null; # requires-python as parsed by pep621.parseRequiresPython
              }
        )
      ) localPackages
    );
})
