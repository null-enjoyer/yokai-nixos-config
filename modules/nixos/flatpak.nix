{ config, pkgs, lib, ... }:

{
  options.desktop.flatpak.packages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "System Flatpak applications to install from Flathub; removal is manual.";
  };

  config = {
    services.flatpak.enable = true;

    systemd.services.flatpak-flathub-remote = {
      description = "Register the Flathub remote for system-wide Flatpak";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.flatpak pkgs.gnugrep ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        remotes=$(flatpak remotes --system --columns=name)
        if ! printf '%s\n' "$remotes" | grep -Fxq flathub; then
          flatpak remote-add --system --if-not-exists \
            flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        fi
      '';
    };

    systemd.services.flatpak-install-apps = lib.mkIf (config.desktop.flatpak.packages != [ ]) {
      description = "Install configured Flathub applications";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "flatpak-flathub-remote.service" ];
      wants = [ "network-online.target" ];
      requires = [ "flatpak-flathub-remote.service" ];
      path = [ pkgs.flatpak ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        for app in ${lib.escapeShellArgs config.desktop.flatpak.packages}; do
          if ! flatpak info --system "$app" >/dev/null 2>&1; then
            flatpak install --system --noninteractive --assumeyes flathub "$app"
          fi
        done
      '';
    };
  };
}
