{
  lib,
  pyproject-nix,
  lock1,
  build,
  ...
}:
let
  inherit (lib)
    composeExtensions
    attrNames
    all
    attrValues
    mapAttrs
    any
    concatMap
    elem
    stringLength
    ;
  inherit (pyproject-nix.lib) pep440 pep508;

  # Compute synthetic conflict extras from the lock's conflicts and the dependency spec.
  #
  # UV uses synthetic markers like `extra == 'group-<len>-<package>-<group>'` in resolution-markers
  # to distinguish packages from different conflict groups. When resolving dependencies, we need
  # to include these synthetic extras in the environment so the markers evaluate correctly.
  #
  # The encoding format is defined in UV's source code:
  # https://github.com/astral-sh/uv/blob/main/crates/uv-resolver/src/universal_marker.rs
  #
  # Specifically, the `encode_package_extra` and `encode_package_group` functions generate:
  # - For extras: `extra-{package_len}-{package}-{extra}`
  # - For groups: `group-{package_len}-{package}-{group}`
  #
  # Where `package_len` is the length of the package name in bytes, which ensures
  # unambiguous parsing since `-` is valid in package/extra names.
  computeConflictExtras =
    let
      packageLen = def: toString (stringLength def.package);
    in
    {
      conflicts,
      spec,
    }:
    concatMap (concatMap (
      def:
      # Not selected
      if !(elem (def.extra or def.group or null) (spec.${def.package} or [ ])) then
        [ ]
      else if def ? group then
        [ "group-${packageLen def}-${def.package}-${def.group}" ]
      else if def ? extra then
        [ "extra-${packageLen def}-${def.package}-${def.extra}" ]
      else
        [ ]
    )) conflicts;

  mkOverlay' =
    {
      uvLock,
      workspaceRoot,
      config,
      sourcePreference,
      environ,
      spec,
      localProjects,
    }:
    final: prev:
    let
      inherit (final) callPackage;

      # Compute synthetic extras for selected conflicts
      conflictExtras = computeConflictExtras {
        inherit (uvLock) conflicts;
        inherit spec;
      };

      # Note: Using Python from final here causes infinite recursion.
      # There is no correct way to override the python interpreter from within the set anyway,
      # so all facts that we get from the interpreter derivation are still the same.
      environ' = pep508.setEnviron (pep508.mkEnviron prev.python) (
        environ
        // {
          # Include both user-provided extras and synthetic conflict extras
          # so that resolution-markers with conflict extras evaluate correctly.
          extra = (environ.extra or [ ]) ++ conflictExtras;
        }
      );
      pythonVersion = environ'.python_full_version.value;

      resolved = lock1.resolveDependencies {
        lock = lock1.filterConflicts {
          lock = uvLock;
          inherit spec;
        };
        environ = environ';
        dependencies = attrNames spec;
      };

      buildRemotePackage = build.remote {
        inherit workspaceRoot config;
        defaultSourcePreference = sourcePreference;
      };

    in
    # Assert that requires-python from uv.lock is compatible with this interpreter
    assert all (spec: pep440.comparators.${spec.op} pythonVersion spec.version) uvLock.requires-python;
    # Assert that supported-environments is compatible with this environment
    assert
      uvLock.supported-markers != { }
      -> any (marker: pep508.evalMarkers environ' marker) (attrValues uvLock.supported-markers);
    # Assert that supported-environments is compatible with this environment
    assert
      uvLock.required-markers != { }
      -> any (marker: pep508.evalMarkers environ' marker) (attrValues uvLock.required-markers);
    mapAttrs (
      name: package:
      # Call different builder functions depending on if package is local or remote (pypi)
      if localProjects ? ${name} then
        callPackage (build.local {
          environ = environ';
          localProject = localProjects.${name};
          inherit package;
        }) { }
      else
        callPackage (buildRemotePackage package) { }
    ) resolved;

in
{

  /*
    Generate an overlay to use with pyproject.nix's build infrastructure.

    See https://pyproject-nix.github.io/pyproject.nix/lib/build.html
  */
  mkOverlay =
    {
      # Whether to prefer sources from either:
      # - wheel
      # - sdist
      #
      # See FAQ for more information.
      sourcePreference,
      # PEP-508 environment customisations.
      # Example: { platform_release = "5.10.65"; }
      environ,
      # Dependency specification used for conflict resolution.
      # By default mkPyprojectOverlay resolves the entire workspace, but that will not work for resolutions with conflicts.
      spec,
      # Local projects loaded from lock1.loadLocalPackages
      localProjects,
      # Workspace config
      config,
      # Workspace root
      workspaceRoot,
      # Lock parsed by lock1.parseLock
      lock,
    }:
    let
      overlay = mkOverlay' {
        inherit
          sourcePreference
          environ
          spec
          localProjects
          config
          workspaceRoot
          ;
        uvLock = lock;
      };
      crossOverlay = composeExtensions (_final: prev: {
        pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope overlay;
        pythonPkgsHostHost = prev.pythonPkgsHostHost.overrideScope overlay;
      }) overlay;
    in
    final: prev:
    let
      inherit (prev) stdenv;
    in
    # When doing native compilation pyproject.nix aliases pythonPkgsBuildHost to pythonPkgsHostHost
    # for performance reasons.
    #
    # Mirror this behaviour by overriding both sets when cross compiling, but only override the
    # build host when doing native compilation.
    if stdenv.buildPlatform != stdenv.hostPlatform then crossOverlay final prev else overlay final prev;

}
