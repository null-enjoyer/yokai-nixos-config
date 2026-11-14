{ config, pkgs, lib, ... }:
{
  wayland.windowManager.hyprland.settings = {
    window_rule = [
      { match.class = "^(org.pulseaudio.pavucontrol)$"; float = true; }
      { match.class = "^(pavucontrol)$"; float = true; }
      { match.class = "^(blueman-manager)$"; float = true; }
      { match.class = "^(nm-connection-editor)$"; float = true; }
      { match.title = "^(Open File)(.*)$"; float = true; }
      { match.title = "^(Save File)(.*)$"; float = true; }
      { match.title = "^(Picture-in-Picture)$"; float = true; }
      { match.title = "^(Picture-in-Picture)$"; pin = true; }
    ];

  };
}
