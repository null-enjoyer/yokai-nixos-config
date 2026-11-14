{ config, pkgs, lib, ... }:
let
  profileRoot = "${config.home.homeDirectory}/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser";
  nativeRoot = "${config.xdg.configHome}/BraveSoftware/Brave-Browser/NativeMessagingHosts";
  # Resolve the manifest on the host, where its executable and libraries are available.
  nativeRelay = name: pkgs.writeTextFile {
    name = "${name}-flatpak-relay";
    executable = true;
    text = ''
      #!/bin/sh
      exec /usr/bin/flatpak-spawn --host --watch-bus ${pkgs.python3}/bin/python3 -c \
        'import json, os, sys; p = json.load(open(sys.argv[1]))["path"]; os.execv(p, [p, *sys.argv[2:]])' \
        ${lib.escapeShellArg "${nativeRoot}/${name}.json"} "$@"
    '';
  };
  nativeManifest = name: description: origins: {
    text = builtins.toJSON {
      inherit name description;
      path = "${nativeRelay name}";
      type = "stdio";
      allowed_origins = origins;
    };
  };
in {
  options.desktop.brave.extraFlatpakArgs = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Additional Flatpak run arguments for Brave.";
  };
  config = lib.mkIf config.programs.brave.enable {
    programs.brave.package = pkgs.callPackage ../../pkgs/brave-flatpak.nix {
      extensionPath = "${config.xdg.configHome}/yokai/browser-extension";
      extraFlatpakArgs = config.desktop.brave.extraFlatpakArgs;
    };

    home.file = {
      "${profileRoot}/NativeMessagingHosts/info.nullflare.yokai_browser.json" = nativeManifest
        "info.nullflare.yokai_browser" "YŌKAI browser search"
        [ "chrome-extension://jbogmlikbcjhlfmmolejemcpnedcnopc/" ];

    };

    # Use the wrapper for desktop launchers and URL handlers.
    xdg.desktopEntries.brave-browser = {
      name = "Brave Web Browser";
      genericName = "Web Browser";
      exec = "${config.programs.brave.finalPackage}/bin/brave %U";
      icon = "com.brave.Browser";
      terminal = false;
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
      actions.new-private-window = {
        name = "New Incognito Window";
        exec = "${config.programs.brave.finalPackage}/bin/brave --incognito %U";
      };
    };
    # The user data directory takes precedence over Flatpak's exported entry.
    xdg.dataFile."applications/com.brave.Browser.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Brave Web Browser
      Exec=${config.programs.brave.finalPackage}/bin/brave %U
      Icon=com.brave.Browser
      NoDisplay=true
    '';

  };
}
