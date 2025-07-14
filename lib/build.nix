{ lib, pyproject-nix, ... }:

let
  inherit (lib)
    intersectLists
    length
    head
    elem
    concatMap
    assertMsg
    match
    elemAt
    listToAttrs
    splitString
    nameValuePair
    optionalAttrs
    versionAtLeast
    findFirst
    optionals
    optional
    unique
    hasPrefix
    mapAttrs
    groupBy
    hasSuffix
    ;
  inherit (pyproject-nix.build.lib) renderers;
  inherit (pyproject-nix.lib) pypa;
  inherit (builtins)
    toJSON
    nixVersion
    replaceStrings
    baseNameOf
    ;

  parseGitURL =
    url:
    let
      # With query params
      m1 = match "([^?]+)\\?([^#]+)#(.+)" url;

      # No query params
      m2 = match "([^#]+)#(.+)" url;
    in
    if m1 != null then
      {
        url = elemAt m1 0;
        query = listToAttrs (
          map (
            s:
            let
              parts = splitString "=" s;
            in
            assert length parts == 2;
            nameValuePair (unquoteURL (elemAt parts 0)) (unquoteURL (elemAt parts 1))
          ) (splitString "&" (elemAt m1 1))
        );
        fragment = unquoteURL (elemAt m1 2);
      }
    else if m2 != null then
      {
        url = elemAt m2 0;
        query = { };
        fragment = unquoteURL (elemAt m2 1);
      }
    else
      throw "Could not parse git url: ${url}";

  mkSpec = dependencies: listToAttrs (map (dep: nameValuePair dep.name dep.extra) dependencies);

  unquoteURL =
    replaceStrings
      [
        "%21"
        "%23"
        "%24"
        "%26"
        "%27"
        "%28"
        "%29"
        "%2A"
        "%2B"
        "%2C"
        "%2F"
        "%3A"
        "%3B"
        "%3D"
        "%3F"
        "%40"
        "%5B"
        "%5D"
      ]
      [
        "!"
        "#"
        "$"
        "&"
        "'"
        "("
        ")"
        "*"
        "+"
        ","
        "/"
        ":"
        ";"
        "="
        "?"
        "@"
        "["
        "]"
      ];

  # `uv pip install` requires precisely matching the expected wheel file names.
  # fetchurl doesn't un-escape the name, leaving percent encoding characters in the filename
  # resulting in install failures.
  srcFilename = url: unquoteURL (baseNameOf url);

in

{
  # Build a local package
  local =
    {
      localProject,
      environ,
      package,
    }:
    {
      stdenv,
      pyprojectHook,
      pyprojectEditableHook,
      resolveBuildSystem,
      # Editable root as a string
      editableRoot ? null,
      darwinMinVersionHook ? null,
    }:
    let
      isEditable = editableRoot != null;

      attrs =
        if !isEditable then
          renderers.mkDerivation
            {
              project = localProject;
              inherit environ;
            }
            {
              inherit pyprojectHook resolveBuildSystem;
            }
        else
          renderers.mkDerivationEditable
            {
              project = localProject;
              inherit environ;
              root = editableRoot;
            }
            {
              inherit
                pyprojectEditableHook
                resolveBuildSystem
                ;

            };

    in
    stdenv.mkDerivation (
      attrs
      // {
        buildInputs =
          (attrs.buildInputs or [ ])
          ++ (optionals (stdenv.isDarwin && darwinMinVersionHook != null) [
            (darwinMinVersionHook stdenv.targetPlatform.darwinSdkVersion)
          ]);

        passthru = attrs.passthru // {
          dependencies =
            # Include build-system dependencies for editable mode by merging pyproject.toml rendered deps with uv.lock
            (optionalAttrs isEditable attrs.passthru.dependencies) // (mkSpec package.dependencies);
          optional-dependencies = mapAttrs (_: mkSpec) package.optional-dependencies;
          dependency-groups = mapAttrs (_: mkSpec) package.dev-dependencies;
        };
      }
      // {
        inherit (package) version;
        pname = package.name;
      }
    );

  /*
    Create a function returning an intermediate attributes set shared between builder implementations
    .
  */
  remote =
    {
      config,
      workspaceRoot,
      defaultSourcePreference,
    }:
    let
      inherit (config)
        no-binary
        no-build
        no-binary-package
        no-build-package
        ;
      unbuildable-packages = intersectLists no-binary-package no-build-package;
    in
    package:
    let

      # Wheels grouped by filename
      wheels = mapAttrs (
        _: whl:
        assert length whl == 1;
        head whl
      ) (groupBy (whl: whl.file'.filename) package.wheels);
      # List of parsed wheels
      wheelFiles = map (whl: whl.file') package.wheels;

    in
    {
      stdenv,
      python,
      fetchurl,
      autoPatchelfHook,
      pythonManylinuxPackages,
      unzip,
      pyprojectHook,
      pyprojectWheelHook,
      sourcePreference ? defaultSourcePreference,
      darwinMinVersionHook ? null,
    }:
    let
      inherit (package) source;
      isGit = source ? git;
      isPypi = source ? registry; # From pypi registry
      isURL = source ? url;
      isPath = source ? path; # Path to sdist

      preferWheel =
        if no-build != null && no-build then
          true
        else if no-binary != null && no-binary then
          false
        else if elem package.name no-binary-package then
          false
        else if elem package.name no-build-package then
          true
        else if sourcePreference == "sdist" then
          false
        else if sourcePreference == "wheel" then
          true
        else
          throw "Unknown sourcePreference: ${sourcePreference}";

      compatibleWheels = pypa.selectWheels stdenv.targetPlatform python wheelFiles;
      selectedWheel' = head compatibleWheels;
      selectedWheel = wheels.${selectedWheel'.filename};

      format =
        if isURL then
          (
            # Package is sdist if the source file is present in the sdist attrset
            if (package.sdist != { }) then "pyproject" else "wheel"
          )
        else if isPypi then
          (
            if preferWheel && compatibleWheels != [ ] then
              "wheel"
            else if package.sdist == { } then
              assert assertMsg (
                compatibleWheels != [ ]
              ) "No compatible wheel, nor sdist found for package '${package.name}' ${package.version}";
              "wheel"
            else
              "pyproject"
          )
        else if isPath then
          (

            if compatibleWheels != [ ] then "wheel" else "pyproject"
          )
        else
          "pyproject";

      gitURL = parseGitURL source.git;

      src =
        if isGit then
          (fetchGit (
            {
              inherit (gitURL) url;
              rev = gitURL.fragment;
            }
            // optionalAttrs (gitURL ? query.tag) { ref = "refs/tags/${gitURL.query.tag}"; }
            // optionalAttrs (versionAtLeast nixVersion "2.4") {
              allRefs = true;
              submodules = true;
            }
          ))
        else if isPath then
          {
            outPath = "${workspaceRoot + "/${source.path}"}";
            passthru.url = source.path;
          }
        else if (isPypi || isURL) && format == "pyproject" then
          fetchurl {
            url = package.source.url or package.sdist.url;
            inherit (package.sdist) hash;
          }
        else if isURL && format == "wheel" then
          let
            wheel = findFirst (
              whl: whl.url == source.url
            ) (throw "Wheel URL ${source.url} not found in list of wheels: ${package.wheels}") package.wheels;
          in
          fetchurl {
            name = srcFilename wheel.url;
            inherit (wheel)
              url
              hash
              ;
          }
        else if format == "wheel" then
          (
            # Fetch wheel from URL
            if selectedWheel ? url then
              if selectedWheel ? hash then
                fetchurl {
                  name = srcFilename selectedWheel.url;
                  inherit (selectedWheel) url hash;
                }
              else
                lib.warn "wheel url '${selectedWheel.url}' missing hash, falling back to builtins.fetchurl" (
                  builtins.fetchurl selectedWheel.url
                )
            # Get wheel from local path
            else if selectedWheel ? path then
              (workspaceRoot + "/${source.registry}/${selectedWheel.path}")
            else
              throw "Internal uv2nix error: unsupported selected wheel: ${toJSON selectedWheel}"
          )
        else
          throw "Unhandled state: could not derive src for package '${package.name}' from: ${toJSON source}";

    in
    # make sure there is no intersection between no-binary-packages and no-build-packages for current package
    assert assertMsg (!elem package.name unbuildable-packages) (
      "There is an overlap between packages specified as no-build and no-binary-package in the workspace. That leaves no way to build these packages: "
      + (toString unbuildable-packages)
    );
    assert assertMsg (
      format == "wheel" -> no-binary != null -> !no-binary
    ) "Package source for '${package.name}' was derived as sdist, in tool.uv.no-binary is set to true";
    assert assertMsg (
      format == "sdist" -> no-build != null -> !no-build
    ) "Package source for '${package.name}' was derived as sdist, in tool.uv.no-build is set to true";
    assert assertMsg (format == "pyproject" -> !elem package.name no-build-package)
      "Package source for '${package.name}' was derived as sdist, but was present in tool.uv.no-build-package";
    assert assertMsg (format == "wheel" -> !elem package.name no-binary-package)
      "Package source for '${package.name}' was derived as wheel, but was present in tool.uv.no-binary-package";
    stdenv.mkDerivation (
      {
        pname = package.name;
        version = "0.0.0";

        inherit src;

        passthru = {
          dependencies = mkSpec package.dependencies;
          optional-dependencies = mapAttrs (_: mkSpec) package.optional-dependencies;
          dependency-groups = mapAttrs (_: mkSpec) package.dev-dependencies;
          inherit package format;
        };

        nativeBuildInputs =
          optional (hasSuffix ".zip" (src.passthru.url or "")) unzip
          ++ optional (format == "pyproject") pyprojectHook
          ++ optional (format == "wheel") pyprojectWheelHook
          ++ optional (format == "wheel" && stdenv.isLinux) autoPatchelfHook;
      }
      // optionalAttrs (package ? version) {
        # Take potentially dynamic fields from uv.lock package
        inherit (package) version;
      }
      // optionalAttrs (format == "wheel") {
        # Don't strip prebuilt wheels
        dontStrip = true;

        # Add wheel utils
        buildInputs =
          # Add manylinux platform dependencies.
          optionals (stdenv.isLinux && stdenv.hostPlatform.libc == "glibc") (
            unique (
              concatMap (
                tag:
                (
                  if hasPrefix "manylinux1" tag then
                    pythonManylinuxPackages.manylinux1
                  else if hasPrefix "manylinux2010" tag then
                    pythonManylinuxPackages.manylinux2010
                  else if hasPrefix "manylinux2014" tag then
                    pythonManylinuxPackages.manylinux2014
                  else if hasPrefix "manylinux_" tag then
                    pythonManylinuxPackages.manylinux2014
                  else
                    [ ] # Any other type of wheel don't need manylinux inputs
                )
              ) selectedWheel'.platformTags
            )
          )
          ++ (optional (stdenv.isDarwin && darwinMinVersionHook != null) (
            darwinMinVersionHook stdenv.targetPlatform.darwinSdkVersion
          ));
      }
      // optionalAttrs (isGit && gitURL ? query.subdirectory) {
        sourceRoot = "source/${gitURL.query.subdirectory}";
      }
    );
}
