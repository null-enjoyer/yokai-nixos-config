{ lib, ... }:
{
  imports = [ ./system-auto-update.nix ./tools-auto-update.nix ./flatpak-auto-update.nix ];
  options.desktop.updates.automatic = {
    enable = lib.mkEnableOption "scheduled system, CLI and Flatpak maintenance";
    systemCalendar = lib.mkOption { type = lib.types.str; default = "weekly"; };
    toolsCalendar = lib.mkOption { type = lib.types.str; default = "*-*-* 05:00:00"; };
    flatpakCalendar = lib.mkOption { type = lib.types.str; default = "daily"; };
    toolsPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Host package providing update-tools; null disables scheduled CLI updates.";
    };
  };
}
