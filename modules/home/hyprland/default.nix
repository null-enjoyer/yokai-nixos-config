{ config, pkgs, lib, ... }:
{
  imports = [
    ./yokai.nix
    ./autostart.nix
    ./keybinds.nix
    ./rules.nix
    ./look.nix
    ./lock-idle.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    # Lua expressions and multi-argument calls use the helpers in lua.nix.
    configType = "lua";
    # The NixOS module owns the compositor and portal packages.
    package = null;
    portalPackage = null;
    systemd.variables = [ "--all" ]; # import the full env into the user systemd/dbus
  };
}
