{ config, lib, pkgs, ... }:
let
  cfg = config.services.lan-drop;
  user = config.users.users.${cfg.user};
  state = "/var/lib/lan-drop";
  url = "http://${cfg.listenAddress}:${toString cfg.port}/";
in {
  options.services.lan-drop = {
    enable = lib.mkEnableOption "LAN file uploads and a shared text field";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing desktop user who owns uploaded files.";
    };
    listenAddress = lib.mkOption {
      type = lib.types.str;
      description = "Local IPv4 address to listen on and include in the QR code.";
    };
    allowedNetwork = lib.mkOption {
      type = lib.types.str;
      description = "IPv4 subnet in CIDR notation allowed to upload files and read shared text.";
    };
    interface = lib.mkOption {
      type = lib.types.str;
      description = "LAN interface on which to open the firewall port.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = "HTTP port for the transfer page.";
    };
    downloadsDirectory = lib.mkOption {
      type = lib.types.strMatching "/.*";
      default = "${user.home}/Downloads";
      defaultText = "~/Downloads for the selected user";
      description = "Directory receiving uploaded files.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = builtins.hasAttr cfg.user config.users.users && user.isNormalUser;
      message = "services.lan-drop.user must name an existing normal user.";
    }];
    networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [ cfg.port ];
    systemd.tmpfiles.rules = [
      "d ${lib.escapeShellArg cfg.downloadsDirectory} 0700 ${cfg.user} ${user.group} - -"
    ];
    environment.systemPackages = [ (pkgs.writeShellScriptBin "lan-drop" ''
      if [[ $# -ne 0 ]]; then echo "Usage: lan-drop" >&2; exit 2; fi
      url=${lib.escapeShellArg url}
      echo "$url"
      ${pkgs.qrencode}/bin/qrencode -t ANSIUTF8 "$url"
    '') ];
    systemd.services.lan-drop = {
      description = "Local file and text transfer";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = user.group;
        ExecStart = lib.escapeShellArgs [
          "${pkgs.python3}/bin/python3" "${../../config/lan-drop}/server.py"
          "--bind" cfg.listenAddress "--port" (toString cfg.port)
          "--network" cfg.allowedNetwork "--downloads" cfg.downloadsDirectory
          "--state" state "--qrencode" "${pkgs.qrencode}/bin/qrencode"
        ];
        StateDirectory = "lan-drop";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "tmpfs";
        BindPaths = [ cfg.downloadsDirectory ];
        ReadWritePaths = [ state cfg.downloadsDirectory ];
        PrivateTmp = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
        IPAddressDeny = "any";
        IPAddressAllow = [ "localhost" cfg.allowedNetwork ];
      };
    };
  };
}
