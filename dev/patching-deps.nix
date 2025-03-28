final: prev: {
  arpeggio =
    (prev.arpeggio.override {
      # We build from sdist (not a wheel) to apply a patch to the source
      # code.
      # Alternatively, if you're using a wheel, you could apply patches to the
      # Python code in `postInstall`/`postFixup`, but YMMV.
      sourcePreference = "sdist";
    }).overrideAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [
          ./arpeggio.patch
        ];

        nativeBuildInputs = old.nativeBuildInputs ++ [
          (final.resolveBuildSystem {
            setuptools = [ ];
          })
        ];
      });
}
