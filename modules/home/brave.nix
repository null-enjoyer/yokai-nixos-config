{ config, pkgs, lib, ... }:
let
  profileRoot = "${config.home.homeDirectory}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser";
  scripts = ../../config/yokai/scripts;
  extensionId = "jbogmlikbcjhlfmmolejemcpnedcnopc";
  extension = pkgs.runCommand "yokai-brave-extension" { } ''
    mkdir -p "$out"
    cp ${../../config/yokai/browser-extension}/* "$out/"
    cp ${../../config/yokai/assets/kitsune-icon.png} "$out/icon.png"
  '';
  extensionPath = "${config.xdg.configHome}/yokai/browser-extension";
  nativeExecutable = pkgs.writeShellScriptBin "yokai-browser-native" ''
    export YOKAI_BRAVE_EXTENSION_ID=${extensionId}
    exec ${pkgs.python3}/bin/python3 ${scripts}/browser_bridge.py native "$@"
  '';
  nativeHost = pkgs.writeTextDir
    "etc/chromium/native-messaging-hosts/info.nullflare.yokai_browser.json"
    (builtins.toJSON {
      name = "info.nullflare.yokai_browser";
      description = "YŌKAI browser search";
      path = "${nativeExecutable}/bin/yokai-browser-native";
      type = "stdio";
      allowed_origins = [ "chrome-extension://${extensionId}/" ];
    });
in {
  config = lib.mkIf (config.desktop.yokai.enable && config.programs.brave.enable) {
    programs.brave = {
      commandLineArgs = [ "--load-extension=${extensionPath}" ];
      nativeMessagingHosts = [ nativeHost ];
    };
    xdg.configFile."yokai/browser-extension".source = extension;
    systemd.user.services.yokai-browser = {
      Unit = {
        Description = "YŌKAI browser search index";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${scripts}/browser_bridge.py --profiles ${lib.escapeShellArg profileRoot} serve";
        Environment = [
          (lib.escapeShellArg "XDG_STATE_HOME=${config.xdg.stateHome}")
          "BRAVE_PATH=${config.programs.brave.finalPackage}/bin/brave"
        ];
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
