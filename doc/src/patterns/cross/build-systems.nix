let
  pyprojectOverrides = final: prev: {
    hatchling = prev.hatchling.overrideAttrs (old: {
      nativeBuildInputs =
        old.nativeBuildInputs
        ++ final.resolveBuildSystem {
          pathspec = [ ];
        };
    });
  };

in
pythonSet.overrideScope (
  lib.composeExtensions (_final: prev: {
    pythonPkgsBuildHost = prev.pythonPkgsBuildHost.overrideScope pyprojectOverrides;
  }) pyprojectOverrides
)
