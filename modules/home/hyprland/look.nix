{ pkgs, lib, ... }:
let
  hlua = import ./lua.nix { inherit lib; };
in
{
  # Curves must be emitted before animations that reference them.
  wayland.windowManager.hyprland.importantPrefixes = [ "curve" "env" "monitor" ];

  wayland.windowManager.hyprland.settings = {
    env = [
      { _args = [ "NIXOS_OZONE_WL" "1" ]; }
      { _args = [ "XCURSOR_SIZE" "24" ]; }
      { _args = [ "SSH_AUTH_SOCK" (hlua.inline ''os.getenv("XDG_RUNTIME_DIR") .. "/ssh-agent"'') ]; }
    ];

    # Additional display definitions belong to the consuming host.
    monitor = [
      { output = ""; mode = "preferred"; position = "auto"; scale = 1; }
    ];

    config = {
      xwayland.force_zero_scaling = true;

      input = {
        kb_layout = lib.mkDefault "us,ru";
        kb_options = lib.mkDefault "grp:caps_toggle";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad.natural_scroll = true;
      };

      general = {
        gaps_in = 0;
        gaps_out = 0;
        # Keep a hit area for native split resizing without drawing an outline.
        border_size = 1;
        col = {
          active_border = "rgba(00000000)";
          inactive_border = "rgba(00000000)";
        };
        layout = "dwindle";
        resize_on_border = true;
        extend_border_grab_area = 15;
        hover_icon_on_border = true;
      };

      decoration = {
        rounding = 0;
        blur = {
          enabled = true;
          size = 4;
          passes = 2;
        };
        shadow = {
          enabled = false;
        };
      };

      animations.enabled = true;

      dwindle = {
        preserve_split = true;
      };

      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
      };
    };

    curve = [
      { _args = [ "ease" { type = "bezier"; points = [ [ 0.25 0.1 ] [ 0.25 1.0 ] ]; } ]; }
    ];
    # Match focus so inactive fullscreen windows receive the same opacity.
    window_rule = [
      { match.focus = false; opacity = "0.94 override"; }
    ];
    animation = [
      { leaf = "windows"; enabled = true; speed = 4; bezier = "ease"; }
      { leaf = "fade"; enabled = true; speed = 4; bezier = "ease"; }
      # The shell reveals attached menus in two stages itself.
      { leaf = "fadePopups"; enabled = false; }
      { leaf = "workspaces"; enabled = true; speed = 4; bezier = "ease"; style = "slidevert"; }
    ];
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  gtk = {
    enable = true;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  home.pointerCursor = {
    gtk.enable = true;
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
  };
}
