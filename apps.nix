{
  nixos = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      # Shell, navigation and system inspection.
      vim neovim ghostty superfile mc tmux
      ripgrep fd bat eza tree fzf zoxide broot
      htop btop duf file which usbutils pciutils

      # Files, archives and command-line utilities.
      gawk gnused jq sqlite
      unzip zip p7zip rsync wl-clipboard
      wget curl dig nmap

      # Browsing, downloads and media.
      vlc

      # Source control, languages and development tools.
      git git-crypt mitmproxy gnumake
      go gopls golangci-lint python3 cargo rustc

    ];

    # Flatpak applications installed from Flathub.
    desktop.flatpak.packages = [ "com.brave.Browser" ];

    # Interactive shell and history.
    programs.zsh.enable = true;
    programs.atuin.enable = true;

    # Development services.
    virtualisation.docker.enable = true;

    # Steam's module also provides its runtime and controller integration.
    programs.steam.enable = true;
  };

  home = { pkgs, ... }: {
    home.packages = with pkgs; [
      # Everyday applications and media.
      telegram-desktop spotify pinta

      # Editors, databases and development tools.
      gcc nodejs_22 postgresql
      vscode

      # Launcher, session controls and desktop integration.
      wlogout
      brightnessctl playerctl pavucontrol
      networkmanagerapplet blueman hyprpolkitagent libnotify wl-clipboard

      # Screenshots, annotation and recording.
      grim slurp satty hyprpicker wf-recorder
      (import ./pkgs/screenrec-toggle.nix { inherit pkgs; })
    ];

    programs.brave.enable = true;

    # Terminal, editor and development environment.
    programs.superfile.enable = true;
    programs.neovim.enable = true;
    programs.git.enable = true;
    programs.gh.enable = true;
    programs.ssh.enable = true;
    services.ssh-agent.enable = true;
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Playback and audio effects.
    programs.mpv.enable = true;
    services.easyeffects.enable = true;
    programs.obs-studio.enable = true;

    # Panel, lock screen, night light and clipboard tools.
    desktop.yokai.enable = true;
    desktop.yokai.telegram.enable = true;
    services.hyprsunset.enable = true;
  };
}
