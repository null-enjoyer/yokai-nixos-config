{ lib, writeShellApplication, quickshell, python3, pulseaudio, grim, slurp, satty, wl-clipboard, systemd, zsh, ghostty, superfile, telegram-desktop, yokai-updates, yokai-clipboard, libnotify, fd, fzf, fontconfig, adwaita-icon-theme, papirus-icon-theme, inter, noto-fonts-cjk-sans, jetbrains-mono, makeFontsConf }:
let
  source = ../config/yokai;
  fonts = makeFontsConf { fontDirectories = [ inter noto-fonts-cjk-sans jetbrains-mono ]; };
in writeShellApplication {
  name = "yokai-shell";
  runtimeInputs = [ quickshell python3 grim slurp satty wl-clipboard pulseaudio systemd zsh ghostty superfile fd fzf fontconfig libnotify ];
  text = ''
    source_path="''${YOKAI_CONFIG:-${source}}"
    wallpaper_path="${../wallpapers}"
    if [[ -d "$source_path/../../wallpapers" ]]; then wallpaper_path="$source_path/../../wallpapers"; fi
    export YOKAI_WALLPAPERS="''${YOKAI_WALLPAPERS:-$wallpaper_path}"
    export FONTCONFIG_FILE=${fonts}
    export XDG_DATA_DIRS="${quickshell}/share:${papirus-icon-theme}/share:${adwaita-icon-theme}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
    export QS_ICON_THEME=Papirus-Dark
    export LC_ALL=en_US.UTF-8
    export QT_QUICK_CONTROLS_STYLE=Basic
    export YOKAI_TELEGRAM_EXEC=${lib.getExe telegram-desktop}
    export YOKAI_CLIPBOARD_EXEC=${yokai-clipboard}/bin/yokai-clipboard
    export YOKAI_UPDATES_EXEC=${lib.getExe yokai-updates}
    # The host may run a live source directory; select its service instance by PID.
    instance_args=(--path "$source_path")
    shell_pid=$(systemctl --user show yokai-shell.service --property=MainPID --value 2>/dev/null || true)
    if [[ "$shell_pid" =~ ^[1-9][0-9]*$ ]]; then instance_args=(--pid "$shell_pid"); fi
    case "''${1:-run}" in
      run) exec quickshell --no-duplicate --path "$source_path" ;;
      dev)
        export YOKAI_DEVELOPMENT=1
        exec quickshell --no-duplicate --path "$source_path"
        ;;
      launcher) exec quickshell ipc "''${instance_args[@]}" call yokai toggle launcher ;;
      close) exec quickshell ipc "''${instance_args[@]}" call yokai close ;;
      clipboard) exec quickshell ipc "''${instance_args[@]}" call yokai clipboard ;;
      screenshot) exec quickshell ipc "''${instance_args[@]}" call yokai screenshot "''${2:-region}" ;;
      updates) exec quickshell ipc "''${instance_args[@]}" call yokai updates ;;
      status) exec quickshell ipc "''${instance_args[@]}" call yokai status ;;
      telegram-login) exec quickshell ipc "''${instance_args[@]}" call yokai-telegram connect ;;
      switch) exec quickshell ipc "''${instance_args[@]}" call yokai switchWindow "''${2:-1}" ;;
      commit) exec quickshell ipc "''${instance_args[@]}" call yokai commit ;;
      workspace) exec quickshell ipc "''${instance_args[@]}" call yokai workspace "''${2:?workspace number required}" ;;
      nightlight) shift; exec python3 "$source_path/scripts/nightlight.py" "$@" ;;
      lock) exec quickshell ipc "''${instance_args[@]}" call yokai-lock lock ;;
      lock-wait)
        quickshell ipc "''${instance_args[@]}" call yokai-lock lock
        python3 - "''${instance_args[@]}" <<'PY'
    import json, subprocess, sys, time
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        try:
            result = subprocess.run(["quickshell", "ipc", *sys.argv[1:], "call", "yokai-lock", "status"], text=True, capture_output=True, timeout=1)
        except subprocess.TimeoutExpired:
            continue
        if result.returncode == 0:
            try:
                state = json.loads(result.stdout)
                if state.get("secure"):
                    sys.exit(0)
                if state.get("state") == "error" and not state.get("locked"):
                    break
            except ValueError:
                pass
        time.sleep(.05)
    print("Session lock was not acknowledged; leaving any pending lock intact", file=sys.stderr)
    sys.exit(1)
    PY
        ;;
      lock-preview) exec quickshell --no-duplicate --path "$source_path/LockPreview.qml" ;;
      suspend) "$0" lock-wait; exec systemctl suspend ;;
      controls)
        quickshell ipc "''${instance_args[@]}" call yokai status >/dev/null
        export YOKAI_CONTROLS_PATH="$source_path/controls.lua"
        expression=$(python3 -c 'import json, os; print("dofile(" + json.dumps(os.environ["YOKAI_CONTROLS_PATH"]) + ")({ replace = true })")')
        hyprctl eval "$expression"
        ;;
      *) echo "Usage: yokai-shell {run|dev|launcher|clipboard|close|screenshot [region|annotate|full]|updates|status|telegram-login|switch [DIRECTION]|commit|workspace NUMBER|controls|nightlight ACTION|lock|lock-wait|lock-preview|suspend}" >&2; exit 2 ;;
    esac
  '';
  meta = { description = "YŌKAI Quickshell desktop"; mainProgram = "yokai-shell"; platforms = lib.platforms.linux; };
}
