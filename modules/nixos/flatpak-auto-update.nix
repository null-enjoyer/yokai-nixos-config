{ config, pkgs, lib, ... }:
let cfg = config.desktop.updates; in
{
  config = lib.mkIf (cfg.enable && cfg.automatic.enable) {
    systemd.services.flatpak-auto-update = {
      description = "Update system Flatpak apps and prune unused runtimes";
      after = [ "network-online.target" "flatpak-flathub-remote.service" ];
      wants = [ "network-online.target" ];
      requires = [ "flatpak-flathub-remote.service" ];
      path = [ pkgs.flatpak pkgs.util-linux pkgs.coreutils "/run/wrappers" ];
      serviceConfig = {
        Type = "oneshot";
        Nice = 10;
        IOSchedulingClass = "idle";
      };
      script = ''
        set -euo pipefail
        sudo -u ${lib.escapeShellArg cfg.user} -H touch ${lib.escapeShellArg cfg.configurationRoot}/.maintenance.lock
        exec 8>${lib.escapeShellArg cfg.configurationRoot}/.maintenance.lock
        flock 8

        echo "== updating system flatpaks =="
        flatpak update --system --noninteractive --assumeyes

        echo "== pruning unused runtimes =="
        flatpak uninstall --system --unused --noninteractive --assumeyes \
          || echo "prune failed; updates themselves succeeded"
      '';
    };

    systemd.timers.flatpak-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.automatic.flatpakCalendar;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
