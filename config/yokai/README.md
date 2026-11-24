# YŌKAI // 神域

A Quickshell desktop with a left rail, search, clipboard history, window previews
and system controls. Ghostty is the terminal. Folders open in `spf`.

[Keyboard shortcuts and screenshots](../../README.md#keyboard-shortcuts) are documented in the repository README.

## Brave and Telegram

Brave uses Flatpak. Native messaging for YŌKAI uses
`flatpak-spawn --host`, granting Brave permission to launch host commands.
The search extension loads from `$XDG_CONFIG_HOME/yokai/browser-extension`.
Fully quit Brave after installation, then launch it and select its profile in the
extension setup. Each profile has its own selection. Reopen setup from the toolbar.

Brave history is indexed locally, including removals. Search works while Brave is
closed. Results open in their recorded profile. URLs keep only the first three
nonempty path segments, without query strings or fragments. Page variants are
merged per profile using the latest title. Only HTTP/HTTPS URLs are accepted.

For Telegram, enable `desktop.yokai.telegram.enable`, choose **Connect Telegram**
or run `yokai-shell telegram-login`. Create credentials at <https://my.telegram.org>,
enter them in setup and scan the QR code. Phone/code and two-step login also work.
The integration owns a separate TDLib session, reads chat/contact metadata without
message history, and opens supported `tg://` links in Telegram Desktop.

## Home Manager

The application catalog enables the shell. Customize it with:

```nix
{
  desktop.yokai = {
    railWidth = 48;
    railExcludedOutputs = [ ];
    launcherKey = "SUPER + space";
    showActiveEmpty = true;
    folderRoots = [ "/home/example" ];
    telegram.enable = true;
  };
}
```

Output exclusions accept connector names or Hyprland `desc:` descriptions.
Geometry and workspace assignments belong to the host. Weather requires
`desktop.yokai.weather` with city, latitude and longitude.

Host QML widgets use `desktop.yokai.networkWidget` or `audioWidget`. Keep companion
files in the same packaged directory. Both receive `theme` and provide their own
`implicitHeight`. A button's `settingsSource` supplies its menu, opened by
`settingsRequested()`. Audio widgets also receive `screen`. Their settings expose
`heading`, `implicitHeight` and writable `menuOpen`.

The update panel is opt-in through `desktop.yokai.updates.enable` and requires the
[host update integration](../../README.md#update). Operations survive closing the shell.

## Move reminders

Left-click the stretching-person icon on the rail to toggle reminders. Right-click for the
interval, application exclusions and a preview. Reminders appear in the center
without taking keyboard focus and can be dismissed or postponed for five minutes.

Exclusions use application classes and support `*` and `?` wildcards. Use **Add**
to include the focused app, then **Save settings**. Reminders pause while a matching
app is open or the session is locked. A fresh interval starts afterwards. Screenshots
temporarily defer the popup without restarting its interval. Unanswered reminders
disappear after 20 seconds.

Defaults live in `desktop.yokai.breakReminder`. Saved menu settings override them.
Reminders are off by default, with a 45-minute interval.

## Appearance and development

Colors: `Theme.qml` and `../ghostty/config`. Backgrounds: repository `wallpapers/`.
Hyprland appearance: `modules/home/hyprland/look.nix` from the repository root.
To run editable QML in Hyprland, use these commands from the repository root:

```sh
YOKAI_CONFIG="$PWD/config/yokai" nix run .#yokai-shell -- dev
YOKAI_CONFIG="$PWD/config/yokai" nix run .#yokai-shell -- controls
```

The managed service uses packaged QML unless the host sets `YOKAI_CONFIG`.

The session lock uses PAM service `yokai-lock`. Preview it with
`yokai-shell lock-preview`. QML reload pauses while locked. Do not manually restart
or reload the lock process. `yokai-shell suspend` waits for secure lock acknowledgement.
The host owns idle and display power-off policy.
