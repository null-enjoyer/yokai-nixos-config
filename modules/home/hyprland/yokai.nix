{ config, pkgs, lib, ... }:
let
  shell = config.desktop.yokai;
  controls = builtins.readFile ../../../config/yokai/controls.lua;
  networkScripts = ../../../config/yokai/scripts;
  clipboardCollector = kind: {
    Unit = {
      Description = "YŌKAI ${kind} clipboard history";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "yokai-clipboard-import.service" ];
      Wants = [ "yokai-clipboard-import.service" ];
    };
    Service = {
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --no-newline --type ${kind} --watch ${pkgs.yokai-clipboard}/bin/yokai-clipboard store --kind ${kind}";
      Environment = [ (lib.escapeShellArg "XDG_STATE_HOME=${config.xdg.stateHome}") ];
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 2;
      StandardOutput = "null";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
in {
  options.desktop.yokai = {
    enable = lib.mkEnableOption "the YŌKAI Quickshell desktop";
    updates.enable = lib.mkEnableOption "the YŌKAI system update panel";
    railWidth = lib.mkOption { type = lib.types.ints.between 28 96; default = 48; description = "Left panel width in logical pixels."; };
    railExcludedOutputs = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Outputs without a left panel, matched by connector name or Hyprland desc: description."; };
    launcherKey = lib.mkOption { type = lib.types.str; default = "SUPER + space"; description = "Keyboard shortcut for control-panel search."; };
    showActiveEmpty = lib.mkOption { type = lib.types.bool; default = true; description = "Keep the focused empty workspace visible until leaving it."; };
    folderRoots = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ config.home.homeDirectory ]; description = "Roots searched for folders in the control panel."; };
    breakReminder = {
      enabled = lib.mkOption { type = lib.types.bool; default = false; description = "Initial movement-reminder state. Saved menu settings take precedence."; };
      intervalMinutes = lib.mkOption { type = lib.types.ints.between 1 1440; default = 45; description = "Initial interval between movement reminders, in minutes."; };
      excludedApps = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; description = "Initial list of application classes or wildcard patterns that pause reminders while open."; };
    };
    audioWidget = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional host QML component between microphone and speakers; receives the shell theme.";
    };
    networkWidget = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional host QML component in the network group. Receives the shell theme as an initial 'theme' property.";
    };
    weather = {
      city = lib.mkOption { type = lib.types.str; default = ""; description = "Weather location label."; };
      latitude = lib.mkOption { type = lib.types.nullOr lib.types.float; default = null; description = "Weather location latitude."; };
      longitude = lib.mkOption { type = lib.types.nullOr lib.types.float; default = null; description = "Weather location longitude."; };
    };
  };
  config = lib.mkIf shell.enable {
    home.packages = [ pkgs.yokai-shell ];
    systemd.user.services.yokai-shell = {
      Unit = { Description = "YŌKAI Quickshell desktop"; PartOf = [ "graphical-session.target" ]; After = [ "graphical-session.target" ]; };
      Service = {
        ExecStart = "${pkgs.yokai-shell}/bin/yokai-shell run";
        Environment = [ "YOKAI_RAIL_WIDTH=${toString shell.railWidth}" (lib.escapeShellArg "YOKAI_RAIL_EXCLUDED_OUTPUTS=${builtins.toJSON shell.railExcludedOutputs}") "YOKAI_SHOW_ACTIVE_EMPTY=${if shell.showActiveEmpty then "1" else "0"}" "YOKAI_TELEGRAM_ENABLED=${if shell.telegram.enable then "1" else "0"}" "YOKAI_UPDATES_ENABLED=${if shell.updates.enable then "1" else "0"}" (lib.escapeShellArg "YOKAI_FOLDER_ROOTS=${builtins.toJSON shell.folderRoots}") ]
          ++ [ (lib.escapeShellArg "YOKAI_BREAK_REMINDER_DEFAULTS=${builtins.toJSON shell.breakReminder}") ]
          ++ lib.optionals (shell.audioWidget != null) [
            (lib.escapeShellArg "YOKAI_AUDIO_WIDGET=${shell.audioWidget}")
          ]
          ++ lib.optionals (shell.networkWidget != null) [
            (lib.escapeShellArg "YOKAI_NETWORK_WIDGET=${shell.networkWidget}")
          ]
          ++ lib.optionals (shell.weather.latitude != null && shell.weather.longitude != null) [
            (lib.escapeShellArg "YOKAI_WEATHER_CITY=${shell.weather.city}")
            "YOKAI_WEATHER_LATITUDE=${toString shell.weather.latitude}"
            "YOKAI_WEATHER_LONGITUDE=${toString shell.weather.longitude}"
          ];
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
    systemd.user.services.yokai-clipboard-import = {
      Unit = {
        Description = "Import clipboard history into YŌKAI";
        PartOf = [ "graphical-session.target" ];
        Before = [ "yokai-clipboard-text.service" "yokai-clipboard-image.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.yokai-clipboard}/bin/yokai-clipboard import-cliphist";
        Environment = [ (lib.escapeShellArg "XDG_STATE_HOME=${config.xdg.stateHome}") ];
        UMask = "0077";
        RemainAfterExit = true;
      };
    };
    systemd.user.services.yokai-clipboard-text = clipboardCollector "text";
    systemd.user.services.yokai-clipboard-image = clipboardCollector "image";
    systemd.user.services.yokai-network-history = {
      Unit.Description = "YŌKAI network traffic history";
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${networkScripts}/network_history.py collect";
        Environment = [ (lib.escapeShellArg "XDG_STATE_HOME=${config.xdg.stateHome}") ];
        UMask = "0077";
        Nice = 10;
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "default.target" ];
    };
    wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''
      local configure_yokai = (function()
      ${controls}
      end)()
      configure_yokai({ replace = true, launcherKey = ${lib.generators.toLua {} shell.launcherKey} })
    '';
  };
}
