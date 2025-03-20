{
  lib,
  ...
}:
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  getSubdirs =
    dir:
    let
      dirContents = builtins.readDir dir; # Reads the current directory
      folders = builtins.attrNames (lib.attrsets.filterAttrs (_: type: type == "directory") dirContents);
    in
    folders;

}
