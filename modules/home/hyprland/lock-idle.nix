{ pkgs, lib, ... }:
{
  systemd.user.services.hyprsunset.Service.ExecStartPre = "${pkgs.yokai-shell}/bin/yokai-shell nightlight ensure";
  xdg.configFile."wlogout/layout".text = lib.mkDefault ''
    {
        "label" : "lock",
        "action" : "${pkgs.yokai-shell}/bin/yokai-shell lock",
        "text" : "Lock",
        "keybind" : "l"
    }
    {
        "label" : "hibernate",
        "action" : "${pkgs.systemd}/bin/systemctl hibernate",
        "text" : "Hibernate",
        "keybind" : "h"
    }
    {
        "label" : "logout",
        "action" : "hyprctl dispatch exit",
        "text" : "Logout",
        "keybind" : "e"
    }
    {
        "label" : "shutdown",
        "action" : "${pkgs.systemd}/bin/systemctl poweroff",
        "text" : "Shutdown",
        "keybind" : "s"
    }
    {
        "label" : "suspend",
        "action" : "${pkgs.yokai-shell}/bin/yokai-shell suspend",
        "text" : "Suspend",
        "keybind" : "u"
    }
    {
        "label" : "reboot",
        "action" : "${pkgs.systemd}/bin/systemctl reboot",
        "text" : "Reboot",
        "keybind" : "r"
    }
  '';
}
