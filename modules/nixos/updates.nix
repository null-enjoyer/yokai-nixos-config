{ config, lib, pkgs, ... }:
let
  cfg = config.desktop.updates;
  user = config.users.users.${cfg.user};
  backendConfig = pkgs.writeText "yokai-updates.json" (builtins.toJSON {
    configurationRoot = cfg.configurationRoot;
    user = cfg.user;
    home = user.home;
    uid = user.uid;
    stateDirectory = "/var/lib/yokai-updates";
    wrapper = "${cfg.configurationRoot}/private/bin/nixos-config";
  });
  start = pkgs.writeShellScript "yokai-updates-start" ''
    export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    exec ${pkgs.yokai-updates}/bin/yokai-updates serve --config ${backendConfig}
  '';
in {
  imports = [ ./maintenance.nix ];
  options.desktop.updates = {
    enable = lib.mkEnableOption "the YŌKAI system update service";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing desktop user who owns update operations.";
    };
    configurationRoot = lib.mkOption {
      type = lib.types.strMatching "/.*";
      description = "Absolute directory containing the public and private configuration checkouts.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.hasAttr cfg.user config.users.users && user.isNormalUser;
      message = "desktop.updates.user must name an existing normal user.";
    }];
    environment.systemPackages = [ pkgs.yokai-updates ];
    systemd.services.yokai-updates = {
      description = "YŌKAI system update service";
      after = [ "network-online.target" ]
        ++ lib.optional (user.uid != null) "user-runtime-dir@${toString user.uid}.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # Activation may replace this unit while it owns an update operation.
      restartIfChanged = false;
      stopIfChanged = false;
      path = [ "/run/wrappers" "/run/current-system/sw" ]
        ++ lib.optional (cfg.automatic.toolsPackage != null) cfg.automatic.toolsPackage;
      environment.HOME = user.home;
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = start;
        RuntimeDirectory = "yokai-updates";
        RuntimeDirectoryMode = "0700";
        StateDirectory = "yokai-updates";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user === ${builtins.toJSON cfg.user}
            && action.id === "org.freedesktop.systemd1.manage-units"
            && ((action.lookup("verb") === "start"
                 && ["flatpak-auto-update.service", "tools-auto-update.service", "system-auto-update.service"].indexOf(action.lookup("unit")) !== -1)
                || (action.lookup("verb") === "restart" && action.lookup("unit") === "yokai-updates.service"))) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
