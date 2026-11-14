{
  imports = [
    (import ../../apps.nix).home
    ./hyprland
    ./brave.nix
    ./brave-flatpak.nix
    ./telegram-search.nix
    ./mpv.nix
    ./shell.nix
    ./superfile.nix
    ./git.nix
    ./neovim.nix
  ];
}
