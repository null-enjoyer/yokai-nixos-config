{ config, pkgs, lib, ... }:
let
  cfg = config.desktop.updates;
  privateRoot = lib.escapeShellArg "${cfg.configurationRoot}/private";
  wrapper = lib.escapeShellArg "${cfg.configurationRoot}/private/bin/nixos-config";
in {
  config = lib.mkIf (cfg.enable && cfg.automatic.enable && cfg.automatic.toolsPackage != null) {
    systemd.services.tools-auto-update = {
      description = "Update CLI tools and activate the NixOS configuration";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ cfg.automatic.toolsPackage pkgs.bash pkgs.jq pkgs.systemd pkgs.util-linux config.nix.package "/run/wrappers" "/run/current-system/sw" ];
      # Activation can update this unit; let its current run finish.
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Nice = 10;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "infinity";
      };
      script = ''
        set -euo pipefail
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
        exec 8>${lib.escapeShellArg cfg.configurationRoot}/.maintenance.lock
        flock 8
        export NIXOS_MAINTENANCE_LOCKED=1

        update-tools --flake ${privateRoot}
        # Activate the checked closure directly after the unlocked-session check.
        # Build logs stay on stderr; stdout contains only the system store path.
        target_system=$(${pkgs.bash}/bin/bash ${wrapper} build)
        ${pkgs.bash}/bin/bash ${wrapper} switch-built "$target_system"
      '';
    };

    systemd.timers.tools-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.automatic.toolsCalendar;
        RandomizedDelaySec = "15min";
        Persistent = true;
      };
    };
  };
}
