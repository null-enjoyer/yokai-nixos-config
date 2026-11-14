{ config, pkgs, lib, ... }:
let
  hlua = import ./lua.nix { inherit lib; };
  inherit (hlua) bind bindWith dsp exec inline toLua;
  mod = "SUPER";
  terminal = "${pkgs.ghostty}/bin/ghostty";
  notify = "${pkgs.libnotify}/bin/notify-send";
  screenshot =
    "${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.wl-clipboard}/bin/wl-copy";
  screenshotAnnotate =
    "${pkgs.grim}/bin/grim -g \"$(${pkgs.slurp}/bin/slurp)\" - | ${pkgs.satty}/bin/satty --filename -";
  screenshotFull = "${pkgs.grim}/bin/grim - | ${pkgs.wl-clipboard}/bin/wl-copy";

  # Hide the focused terminal, or bring a hidden terminal onto this workspace.
  terminalToggle = inline ''
    function()
      local class = "com.mitchellh.ghostty"
      local active = hl.get_active_window()
      if active ~= nil and active.class == class then
        hl.dispatch(hl.dsp.window.move({ window = active, workspace = "special:hidden", follow = false }))
        return
      end

      local terminal = nil
      for _, window in ipairs(hl.get_windows()) do
        if window.mapped and window.class == class then
          terminal = window
          if window.workspace ~= nil and window.workspace.addressable_name == "special:hidden" then break end
        end
      end
      if terminal == nil then
        hl.dispatch(hl.dsp.exec_cmd(${toLua terminal}))
        return
      end
      local workspace = hl.get_active_workspace()
      if workspace == nil then return end
      hl.dispatch(hl.dsp.window.move({ window = terminal, workspace = workspace, follow = false }))
      hl.dispatch(hl.dsp.focus({ window = terminal }))
    end
  '';

  workspaceBinds = lib.concatMap (i:
    let key = toString (lib.mod i 10);
    in [
      (bind "${mod} + ${key}" (dsp "focus({ workspace = ${toString i} })"))
      (bind "${mod} + SHIFT + ${key}" (dsp "window.move({ workspace = ${toString i} })"))
    ]) (lib.range 1 10);
in
{
  wayland.windowManager.hyprland.settings.bind = [
    (bind "${mod} + Return" (exec terminal))
    (bind "CTRL + ALT + space" terminalToggle)
    (bind "${mod} + Q" (dsp "window.close()"))
    (bind "${mod} + E" (exec "${terminal} -e ${pkgs.superfile}/bin/spf"))
    (bind "${mod} + A" (exec "${pkgs.pavucontrol}/bin/pavucontrol"))
    (bind "${mod} + Escape" (exec "${pkgs.wlogout}/bin/wlogout"))
    (bind "${mod} + F" (dsp "window.fullscreen()"))
    (bind "${mod} + space" (dsp "window.float()"))
    (bind "${mod} + J" (dsp ''layout("togglesplit")''))

    (bind "${mod} + S" (dsp ''workspace.toggle_special("magic")''))
    (bind "${mod} + SHIFT + S" (dsp ''window.move({ workspace = "special:magic" })''))

    (bind "Print" (exec (if config.desktop.yokai.enable then "${pkgs.yokai-shell}/bin/yokai-shell screenshot region" else screenshot)))
    (bind "${mod} + Print" (exec (if config.desktop.yokai.enable then "${pkgs.yokai-shell}/bin/yokai-shell screenshot annotate" else screenshotAnnotate)))
    (bind "SHIFT + Print" (exec (if config.desktop.yokai.enable then "${pkgs.yokai-shell}/bin/yokai-shell screenshot full" else screenshotFull)))
    (bind "${mod} + SHIFT + C" (exec "${pkgs.hyprpicker}/bin/hyprpicker -a"))
    (bind "${mod} + SHIFT + R" (exec "screenrec-toggle"))

    (bind "${mod} + left" (dsp ''focus({ direction = "l" })''))
    (bind "${mod} + right" (dsp ''focus({ direction = "r" })''))
    (bind "${mod} + up" (dsp ''focus({ direction = "u" })''))
    (bind "${mod} + down" (dsp ''focus({ direction = "d" })''))

    (bind "${mod} + SHIFT + left" (dsp ''window.move({ direction = "l" })''))
    (bind "${mod} + SHIFT + right" (dsp ''window.move({ direction = "r" })''))
    (bind "${mod} + SHIFT + up" (dsp ''window.move({ direction = "u" })''))
    (bind "${mod} + SHIFT + down" (dsp ''window.move({ direction = "d" })''))

    (bind "${mod} + G" (inline ''
      function()
        hl.dispatch(hl.dsp.submap("passthrough"))
        hl.dispatch(hl.dsp.exec_cmd(${toLua ''${notify} -t 1500 "Hyprland" "Passthrough ON — shortcuts off (Super+G to exit)"''}))
      end''))

    (bindWith { mouse = true; } "${mod} + mouse:272" (dsp "window.drag()"))
    (bindWith { mouse = true; } "${mod} + mouse:273" (dsp "window.resize()"))

    (bindWith { repeating = true; } "${mod} + CTRL + left" (dsp "window.resize({ x = -40, y = 0, relative = true })"))
    (bindWith { repeating = true; } "${mod} + CTRL + right" (dsp "window.resize({ x = 40, y = 0, relative = true })"))
    (bindWith { repeating = true; } "${mod} + CTRL + up" (dsp "window.resize({ x = 0, y = -40, relative = true })"))
    (bindWith { repeating = true; } "${mod} + CTRL + down" (dsp "window.resize({ x = 0, y = 40, relative = true })"))

    (bindWith { repeating = true; locked = true; } "XF86AudioRaiseVolume"
      (exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
    (bindWith { repeating = true; locked = true; } "XF86AudioLowerVolume"
      (exec "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
    (bindWith { repeating = true; locked = true; } "XF86AudioMute"
      (exec "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
    (bindWith { repeating = true; locked = true; } "XF86MonBrightnessUp"
      (exec "${pkgs.brightnessctl}/bin/brightnessctl set 5%+"))
    (bindWith { repeating = true; locked = true; } "XF86MonBrightnessDown"
      (exec "${pkgs.brightnessctl}/bin/brightnessctl set 5%-"))

    (bindWith { locked = true; } "XF86AudioPlay" (exec "${pkgs.playerctl}/bin/playerctl play-pause"))
    (bindWith { locked = true; } "XF86AudioNext" (exec "${pkgs.playerctl}/bin/playerctl next"))
    (bindWith { locked = true; } "XF86AudioPrev" (exec "${pkgs.playerctl}/bin/playerctl previous"))
  ] ++ workspaceBinds;

  wayland.windowManager.hyprland.submaps.passthrough.settings.bind = [
    {
      _args = [
        "${mod} + G"
        (inline ''
          function()
            hl.dispatch(hl.dsp.submap("reset"))
            hl.dispatch(hl.dsp.exec_cmd(${toLua ''${notify} -t 1500 "Hyprland" "Passthrough OFF"''}))
          end'')
      ];
    }
  ];
}
