{ pkgs }:
pkgs.writeShellScriptBin "screenrec-toggle" ''
    if ${pkgs.procps}/bin/pgrep -x wf-recorder >/dev/null; then
      ${pkgs.procps}/bin/pkill -INT -x wf-recorder
      ${pkgs.libnotify}/bin/notify-send "Screen recording" "Saved to ~/Videos"
    else
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/Videos"
      geom=$(${pkgs.slurp}/bin/slurp) || exit 0
      ${pkgs.libnotify}/bin/notify-send "Screen recording" "Recording started"
      ${pkgs.wf-recorder}/bin/wf-recorder -g "$geom" \
        -f "$HOME/Videos/rec-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S).mp4"
    fi
  ''
