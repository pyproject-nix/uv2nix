{
  lib,
  pkgs,
  system,
  pythonSet,
  self,
  ...
}:
let
  venv = self.packages.${system}.venv;
in
pkgs.stdenv.mkDerivation {
  name = "django-webapp-static";
  inherit (pythonSet.django-webapp) src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    venv
  ];

  installPhase = ''
    env DJANGO_STATIC_ROOT="$out" python manage.py collectstatic
  '';
}
