{
  pkgs,
  lib,
  system,
  self,
  ...
}:
let
  inherit (self.packages.${system}) venv;
in
pkgs.mkShell {
  packages = [
    pkgs.uv
    pkgs.python312
  ];
  env = {
    UV_NO_SYNC = "1";
    UV_PYTHON = "${venv}/bin/python";
    UV_PYTHON_DOWNLOADS = "never";
  };
  shellHook = ''
    unset PYTHONPATH
    export REPO_ROOT=$(git rev-parse --show-toplevel)
  '';
}
