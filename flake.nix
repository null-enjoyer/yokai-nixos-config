{
  description = "A modular NixOS desktop with Hyprland and Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hyprland retains its own nixpkgs input for its upstream binary cache.
    hyprland.url = "github:hyprwm/Hyprland";
    nixpkgs-pinned.url = "github:NixOS/nixpkgs/241313f4e8e508cb9b13278c2b0fa25b9ca27163";
  };

  outputs = { self, nixpkgs, home-manager, hyprland, ... }@inputs:
    let
      system = "x86_64-linux";
      overlay = import ./overlays { inherit inputs; };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ overlay ];
        config.allowUnfree = true;
      };
    in {
      overlays.default = overlay;

      nixosModules = {
        default = self.nixosModules.desktop;
        desktop = {
          imports = [
            hyprland.nixosModules.default
            home-manager.nixosModules.home-manager
            ./modules/nixos
          ];
          nixpkgs.overlays = [ overlay ];
        };
        flatpak = ./modules/nixos/flatpak.nix;
        updates = ./modules/nixos/updates.nix;
      };

      homeManagerModules = {
        default = self.homeManagerModules.desktop;
        desktop = ./modules/home;
      };

      packages.${system} = {
        inherit (pkgs) ghostty yokai-shell yokai-updates yokai-clipboard;
        default = pkgs.yokai-shell;
      };

      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./examples/desktop.nix
          {
            home-manager.users.demo.imports = [ self.homeManagerModules.default ];
          }
        ];
      };

      checks.${system} = {
        scripts = pkgs.runCommand "desktop-script-checks" {
          nativeBuildInputs = with pkgs; [ bash (python3.withPackages (packages: [ packages.pillow ])) nodejs_22 coreutils jq gnused gnugrep gawk util-linux ];
        } ''
          bash -n ${./config/yokai/scripts/screenshot.sh}
          python3 ${./tests/screenshot.py} ${./config/yokai/scripts/screenshot.sh}
          python3 ${./tests/test_clipboard.py} --scripts ${./config/yokai/scripts}
          python3 ${./tests/network-history.py} --scripts ${./config/yokai/scripts}
          python3 ${./tests/browser-search.py} --script ${./config/yokai/scripts/browser_bridge.py}
          python3 ${./tests/telegram-search.py} --script ${./config/yokai/scripts}/telegram_search.py
          python3 ${./tests/system-updates.py} --script ${./scripts/yokai-updates.py}
          node ${./tests/browser-extension.js} --source ${./config/yokai/browser-extension/background.js}
          node ${./tests/search-ranking.js} --source ${./config/yokai/Fuzzy.js}
          node ${./tests/update-status.js} --source ${./config/yokai/UpdateStatus.js}
          touch "$out"
        '';
        # Forces module assertions and generation of the complete example config.
        example = self.nixosConfigurations.example.config.system.build.toplevel;
      };
    };
}
