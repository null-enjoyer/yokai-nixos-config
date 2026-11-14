{ pkgs, ... }:
{
  networking.hostName = "demo";
  networking.networkmanager.enable = true;
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Replace this example filesystem and boot setup with generated hardware config.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/EFI"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "sd_mod" ];
  nixpkgs.config.allowUnfree = true;

  users.users.demo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.demo = {
      home = {
        username = "demo";
        homeDirectory = "/home/demo";
        stateVersion = "26.05";
      };
      programs.home-manager.enable = true;
    };
  };
  system.stateVersion = "26.05";
}
