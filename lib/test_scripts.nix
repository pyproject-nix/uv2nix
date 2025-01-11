{ lib, scripts, ... }:

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
        filterAttrs (
          name: type: type == "regular" && hasSuffix ".py" name
        ) (readDir ./fixtures/inline-metadata)
      );
in

{

  loadScript.config = {
    testTrivial = {
      expr = scripts'."trivial.py".config;
      expected = {
        no-binary = false;
        no-binary-package = [ ];
        no-build = false;
        no-build-package = [ ];
      };
    };

    testConfig = {
      expr = scripts'."config.py".config;
      expected = {
        no-binary = true;
        no-binary-package = [ ];
        no-build = false;
        no-build-package = [ ];
      };
    };
  };

}
