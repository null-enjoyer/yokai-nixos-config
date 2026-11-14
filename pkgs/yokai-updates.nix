{ lib, writeShellApplication, python3, nix, systemd, git, bash, flatpak, coreutils, util-linux, jq, gh }:
writeShellApplication {
  name = "yokai-updates";
  runtimeInputs = [ python3 nix systemd git bash flatpak coreutils util-linux jq gh ];
  text = ''
    exec python3 ${../scripts/yokai-updates.py} "$@"
  '';
  meta = {
    description = "YŌKAI system update service and client";
    mainProgram = "yokai-updates";
    platforms = lib.platforms.linux;
  };
}
