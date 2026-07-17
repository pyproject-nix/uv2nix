{
  lib,
  scripts,
  pkgs,
  pyproject-nix,
  ...
}:

let
  inherit (lib) mapAttrs filterAttrs hasSuffix;
  inherit (builtins) readDir;

  scripts' =
    mapAttrs
      (
        name: _:
        scripts.loadScript {
          script = ./fixtures/inline-metadata + "/${name}";
        }
      )
      (
        filterAttrs (name: type: type == "regular" && hasSuffix ".py" name) (
          readDir ./fixtures/inline-metadata
        )
      );
in

{

  loadScript.config = {
    testTrivial = {
      expr = scripts'."trivial.py".config;
      expected = {
        compile-bytecode = true;
        no-binary = false;
        no-binary-package = [ ];
        no-build = false;
        no-build-package = [ ];
        extra-build-dependencies = { };
        extra-build-variables = { };
        config-settings = { };
        config-settings-package = { };
      };
    };

    testConfig = {
      expr = scripts'."config.py".config;
      expected = {
        compile-bytecode = true;
        no-binary = true;
        no-binary-package = [ ];
        no-build = false;
        no-build-package = [ ];
        extra-build-dependencies = { };
        extra-build-variables = { };
        config-settings = { };
        config-settings-package = { };
      };
    };
  };

  # Regression test: a script's dependency spec is built from PEP-508
  # requirements which expose `.extras`. Previously mkOverlay read `.extra`,
  # which is only present on uv.lock dependency edges; this stayed hidden
  # until the spec's values were forced by conflict handling.
  loadScript.mkOverlay = {
    testSpecForcedByConflicts = {
      expr =
        let
          overlay = scripts'."conflicts.py".mkOverlay { sourcePreference = "wheel"; };
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              overlay;
        in
        pythonSet.arpeggio.version;
      expected = "2.0.2";
    };
  };

}
