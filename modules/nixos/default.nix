{
  imports = [
    (import ../../apps.nix).nixos
    ./audio.nix
    ./desktop.nix
    ./fonts.nix
    ./flatpak.nix
    ./keyboard.nix
    ./nix.nix
    ./shell.nix
    ./nix-ld.nix
    ./updates.nix
    ./lan-drop.nix
  ];
}
