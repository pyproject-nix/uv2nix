# Shipping applications

`uv2nix` primarily builds [_virtual environments_](https://docs.python.org/3/library/venv.html), not individual applications.

Sometimes the fact that an application is written in Python & using a virtualenv is an implementation detail that you don't want to expose in your Nix package.

For such cases `pyproject.nix` provides a utility function [`mkApplication`](https://pyproject-nix.github.io/pyproject.nix/build/util.html#function-library-build.util.mkApplication):

``` nix
{
    packages = forAllSystems (
      system:
      let
        pythonSet = pythonSets.${system};
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;
      in
      {
        # Create a derivation that wraps the venv but that only links package
        # content present in pythonSet.hello-world.
        #
        # This means that files such as:
        # - Python interpreters
        # - Activation scripts
        # - pyvenv.cfg
        #
        # Are excluded but things like binaries, man pages, systemd units etc are included.
        default = util.mkApplication {
          venv = pythonSet.mkVirtualEnv "application-env" workspace.deps.default;
          package = pythonSet.hello-world;
      };

        # If you are building a package within a workspace, and want to avoid
        # including the dependencies of all members of your workspace,
        # instead of just the packages that your application needs.
        app = util.mkApplication {
          venv = pythonSet.mkVirtualEnv "application-env" {
            app = [ ];
          };
          package = pythonSet.hello-world;
        };
}
```