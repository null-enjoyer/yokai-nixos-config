{ config, pkgs, lib, ... }:
{
  # Run after Home Manager imports the compositor environment into systemd.
  wayland.windowManager.hyprland.extraConfig =
    let hlua = import ./lua.nix { inherit lib; };
    in ''
      hl.on("hyprland.start", function()
        hl.exec_cmd(${hlua.toLua "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"})
        hl.exec_cmd(${hlua.toLua "${pkgs.blueman}/bin/blueman-applet"})
        hl.exec_cmd(${hlua.toLua "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"})
      end)
    '';

}
