{ config, pkgs, lib, ... }:
let
  cfg = config.desktop.updates;
  wrapper = lib.escapeShellArg "${cfg.configurationRoot}/private/bin/nixos-config";
in {
  config = lib.mkIf (cfg.enable && cfg.automatic.enable) {
    systemd.services.system-auto-update = {
      description = "Update flake inputs and build the next-boot generation";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.jq pkgs.util-linux config.nix.package pkgs.nixos-rebuild "/run/wrappers" "/run/current-system/sw" ];
      serviceConfig = {
        Type = "oneshot";
        Nice = 10;
        IOSchedulingClass = "idle";
        RuntimeDirectory = "system-auto-update";
        RuntimeDirectoryMode = "0711";
      };
      script = ''
        set -euo pipefail
        asuser() { sudo -u ${lib.escapeShellArg cfg.user} -H "$@"; }
        asuser touch ${lib.escapeShellArg cfg.configurationRoot}/.maintenance.lock
        exec 8>${lib.escapeShellArg cfg.configurationRoot}/.maintenance.lock
        flock 8
        export NIXOS_MAINTENANCE_LOCKED=1
        token=$(asuser /etc/profiles/per-user/${lib.escapeShellArg cfg.user}/bin/gh auth token 2>/dev/null || true)
        nixconf="$RUNTIME_DIRECTORY/nix.conf"
        : > "$nixconf"
        chmod 600 "$nixconf"
        chown ${lib.escapeShellArg cfg.user} "$nixconf"
        if [ -n "$token" ]; then
          printf 'access-tokens = github.com=%s\n' "$token" > "$nixconf"
        else
          echo "warning: no gh token available — GitHub API calls may be rate-limited"
        fi
        unset token

        # Keep credentials out of sudo arguments; updates remain user-owned.
        asuser env NIXOS_MAINTENANCE_LOCKED="$NIXOS_MAINTENANCE_LOCKED" NIX_USER_CONF_FILES="$nixconf" ${pkgs.bash}/bin/bash ${wrapper} update-inputs
        out=$(asuser env NIXOS_MAINTENANCE_LOCKED="$NIXOS_MAINTENANCE_LOCKED" NIX_USER_CONF_FILES="$nixconf" ${pkgs.bash}/bin/bash ${wrapper} build)
        [ -n "$out" ] || { echo "build produced no output path"; exit 1; }
        nix-env -p /nix/var/nix/profiles/system --set "$out"
        "$out"/bin/switch-to-configuration boot
        echo "done — new generation activates on next reboot"
      '';
    };
    systemd.timers.system-auto-update = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.automatic.systemCalendar;
        Persistent = true;
        RandomizedDelaySec = "30min";
      };
    };
  };
}
