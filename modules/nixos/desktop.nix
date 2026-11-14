{ pkgs, ... }:
let
  yokaiTheme = pkgs.callPackage ../../pkgs/yokai-sddm-theme.nix { };
in
{
  networking.networkmanager.enable = true;
  services.xserver.enable = true;
  services.displayManager.sddm = {
    enable = true;
    theme = "${yokaiTheme}/share/sddm/themes/yokai";
  };
  fonts.packages = [ pkgs.inter ];
  programs.hyprland.enable = true;
  # The Quickshell session locker authenticates through this dedicated PAM service.
  security.pam.services.yokai-lock = { };
  services.printing.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;
  hardware.graphics.enable = true;
}
