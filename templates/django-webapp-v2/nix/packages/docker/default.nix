{
  lib,
  pkgs,
  system,
  package-name,
  self,
  ...
}:
let
  venv = self.packages.${system}.venv;
in
lib.optionalAttrs pkgs.stdenv.isLinux
  # Expose Docker container in packages
  pkgs.dockerTools.buildLayeredImage
  {
    name = "${package-name}";
    contents = [ pkgs.cacert ];
    config = {
      Cmd = [
        "${venv}/bin/python"
      ];
      Env = [
        "DJANGO_SETTINGS_MODULE=${self.settingsModules.prod}"
        "DJANGO_STATIC_ROOT=${self.packages.${system}.${package-name}.static}"
      ];
    };
  }
