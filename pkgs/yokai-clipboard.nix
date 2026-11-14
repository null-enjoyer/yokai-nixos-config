{ writeShellApplication, python3, wl-clipboard, cliphist }:
let
  python = python3.withPackages (packages: [ packages.pillow ]);
in writeShellApplication {
  name = "yokai-clipboard";
  runtimeInputs = [ python wl-clipboard cliphist ];
  text = ''
    exec python3 ${../config/yokai/scripts/clipboard.py} "$@"
  '';
  meta.description = "YŌKAI clipboard history";
}
