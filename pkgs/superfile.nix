{ symlinkJoin, superfile }:
symlinkJoin {
  name = "superfile-${superfile.version}";
  inherit (superfile) version;
  paths = [ superfile ];
  postBuild = ''
    ln -s superfile "$out/bin/spf"
  '';
  meta = superfile.meta // { mainProgram = "spf"; };
}
