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
    ;
  inherit (pyproject-nix.lib) pep440 pep508;

  mkOverlay' =
    {
      uvLock,
      workspaceRoot,
      config,
      sourcePreference,
      environ,
      spec,
      localPackages,
    }:
    final: prev:
    let
      inherit (final) callPackage;

      # Note: Using Python from final here causes infinite recursion.
      # There is no correct way to override the python interpreter from within the set anyway,
      # so all facts that we get from the interpreter derivation are still the same.
      environ' = pep508.setEnviron (pep508.mkEnviron prev.python) environ;
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
    assert all (marker: pep508.evalMarkers environ' marker) (attrValues uvLock.supported-markers);
    mapAttrs (
      name: package:
      # Call different builder functions depending on if package is local or remote (pypi)
      if localPackages ? ${name} then
        callPackage (build.local {
          environ = environ';
          localProject = localPackages.${name};
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
      localPackages,
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
          localPackages
          config
          workspaceRoot
          ;
        uvLock = lock;
      };
      crossOverlay = composeExtensions (_final: prev: {
        pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope overlay;
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
