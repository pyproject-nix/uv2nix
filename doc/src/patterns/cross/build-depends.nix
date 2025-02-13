final: prev: {

  foobar = prev.foobar.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [
      final.pkgs.buildPackages.cmake
    ];

    buildInputs = (old.buildInputs or [ ]) ++ [ final.pkgs.ncurses ];
  });

}
