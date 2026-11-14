{ config, pkgs, lib, ... }:
let
  scripts = ../../config/yokai/scripts;
in {
  options.desktop.yokai.telegram.enable = lib.mkEnableOption "Telegram chat search in YŌKAI";
  config = lib.mkIf (config.desktop.yokai.enable && config.desktop.yokai.telegram.enable) {
    systemd.user.services.yokai-telegram = {
      Unit = {
        Description = "YŌKAI Telegram chat search";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${scripts}/telegram_search.py serve";
        Environment = [
          (lib.escapeShellArg "XDG_STATE_HOME=${config.xdg.stateHome}")
          "TDJSON_PATH=${pkgs.tdlib}/lib/libtdjson.so"
          "QR_ENCODE=${pkgs.qrencode}/bin/qrencode"
          "TELEGRAM_PATH=${lib.getExe pkgs.telegram-desktop}"
        ];
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
