{
  workspace,
  pkgs,
  lib,
  pyproject-nix,
  ...
}:
let
  inherit (lib) nameValuePair listToAttrs optionalAttrs;
in

{
  mkOverlay =
    let
      mkTest =
        workspaceRoot:
        {
          packages,
          environ ? { },
          # Ambigious resolution
          dependencies ? { },
        }:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };

          overlay = ws.mkPyprojectOverlay (
            {
              sourcePreference = "wheel";
              inherit environ;
            }
            // optionalAttrs (dependencies != { }) {
              inherit dependencies;
            }
          );

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              overlay;
        in
        listToAttrs (map (name: nameValuePair name pythonSet.${name}.version) packages);

    in
    {
      testTrivial = {
        expr = mkTest ./fixtures/trivial { packages = [ "arpeggio" ]; };
        expected = {
          arpeggio = "2.0.2";
        };
      };

      testKitchenSink = {
        expr = mkTest ./fixtures/kitchen-sink/a { packages = [ "pip" ]; };
        expected = {
          pip = "20.3.1";
        };
      };

      testWorkspace = {
        expr = mkTest ./fixtures/workspace {
          packages = [
            "arpeggio"
            "workspace-package"
          ];
        };
        expected = {
          arpeggio = "2.0.2";
          workspace-package = "0.1.0";
        };
      };

      testWorkspaceFlat = {
        expr = mkTest ./fixtures/workspace-flat {
          packages = [
            "pkg-a"
            "pkg-b"
          ];
        };
        expected = {
          pkg-a = "0.1.0";
          pkg-b = "0.1.0";
        };
      };

      testSupportedMarkersOK = {
        expr = mkTest ./fixtures/with-tool-uv-environments { packages = [ "with-tool-uv-environments" ]; };
        expected = {
          with-tool-uv-environments = "0.1.0";
        };
      };

      testSupportedMarkersFail = {
        expr = mkTest ./fixtures/with-tool-uv-environments {
          packages = [ "with-tool-uv-environments" ];
          environ = {
            sys_platform = "templeos";
          };
        };
        expectedError.type = "AssertionError";
      };

      testConflictsIndexBoth = {
        expr = mkTest ../lib/fixtures/conflicts-index {
          packages = [ "conflicts-index" ];
          dependencies = {
            conflicts-index = [
              "group-a"
              "group-b"
            ];
          };
        };
        expectedError.type = "ThrownError";
        expectedError.msg = "resolution still ambigious";
      };
    };

}
