{ lib, ... }:
{
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = lib.mkDefault "daily";
    options = lib.mkDefault "--delete-older-than 10d";
  };
  nix.settings = {
    auto-optimise-store = lib.mkDefault true;
    experimental-features = [ "nix-command" "flakes" ];
    # Keep Hyprland's own nixpkgs input so its cached dependency builds match.
    substituters = [ "https://hyprland.cachix.org" ];
    trusted-public-keys = [
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc"
    ];
  };
}
