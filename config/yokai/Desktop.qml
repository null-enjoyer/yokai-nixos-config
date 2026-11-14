pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Singleton {
    id: root
    property string mode: "closed"
    property string query: ""
    readonly property bool opened: mode !== "closed"
    property var screen: null
    property var panelMenu: null
    property bool screenshotActive: false
    property var clipboardTarget: null
    function rememberClipboardTarget() {
        const window = ToplevelManager.activeToplevel;
        clipboardTarget = window ? {address: window.HyprlandToplevel.address, appId: window.appId} : null;
    }
    function clipboard(targetScreen) {
        closePanelMenu();
        if (mode === "clipboard") { close(); return; }
        if (!opened) rememberClipboardTarget();
        screen = targetScreen ?? focusedScreen();
        query = "";
        Switcher.prepare();
        mode = "clipboard";
    }
    function closePanelMenu() {
        const menu = panelMenu;
        panelMenu = null;
        if (menu) menu.closeReveal(true);
    }
    function focusedScreen() {
        const monitor = Compositor.monitors.find(item => item.focused);
        return Quickshell.screens.find(item => item.name === monitor?.name) ?? Quickshell.screens[0];
    }
    function search(targetScreen) {
        closePanelMenu();
        if (mode === "apps" || mode === "folders") { close(); return; }
        if (!opened) rememberClipboardTarget();
        screen = targetScreen ?? focusedScreen();
        query = "";
        Switcher.prepare();
        mode = "apps";
    }
    function enterWindows() {
        closePanelMenu();
        if (!opened) { rememberClipboardTarget(); screen = focusedScreen(); }
        query = "";
        Switcher.prepare();
        mode = "windows";
    }
    function toggle(name, targetScreen) {
        if (name === "launcher" || name === "settings") search(targetScreen);
    }
    function close() { mode = "closed"; query = ""; FolderSearch.query = ""; Switcher.cancel(); }
    function launchApplication(app) {
        if (!app || app.command.length === 0) return;
        const args = ["systemd-run", "--user", "--scope", "--collect", "--slice=app.slice"];
        if (app.workingDirectory) args.push("--working-directory=" + app.workingDirectory);
        args.push("--");
        if (app.runInTerminal) {
            args.push("ghostty", "--gtk-single-instance=false");
            if (app.workingDirectory) args.push("--working-directory=" + app.workingDirectory);
            args.push("-e");
        }
        Quickshell.execDetached([...args, ...app.command]);
        close();
    }
    function openFolder(path) {
        if (!path) return;
        Quickshell.execDetached(["systemd-run", "--user", "--scope", "--collect", "--slice=app.slice",
            "--", "ghostty", "--gtk-single-instance=false", "--working-directory=" + path,
            "-e", "zsh", "-ic", 'spf "$1"; exec zsh', "yokai-folder", path]);
        close();
    }
    function openBrowserResult(result) { BrowserSearch.open(result); }
    function openTelegramResult(result) { TelegramSearch.open(result); }
    function screenshot(kind) {
        if (screenshotActive || LockScreen.locked || !["region", "annotate", "full"].includes(kind)) return;
        screenshotActive = true;
        screenshotProcess.command = ["bash", Quickshell.shellPath("scripts/screenshot.sh"), kind];
        // Release popup grabs before the selector maps its input surface.
        Qt.callLater(() => screenshotProcess.running = true);
    }
    Process {
        id: screenshotProcess
        onExited: root.screenshotActive = false
    }
    signal updatesRequested()
    IpcHandler {
        target: "yokai"
        function toggle(name: string): void { root.toggle(name); }
        function close(): void { root.close(); }
        function clipboard(): void { root.clipboard(); }
        function screenshot(kind: string): void { root.screenshot(kind); }
        function updates(): void { root.updatesRequested(); }
        function workspace(address: string): void { Compositor.focusWorkspace(address); }
        function switchWindow(direction: int): void { Switcher.step(direction); }
        function commit(): void { Switcher.commit(); }
        function status(): string {
            return JSON.stringify({mode: root.mode, panelMenu: root.panelMenu?.heading ?? null, screenshotActive: root.screenshotActive, width: Theme.railWidth, keyboardLayout: Compositor.keyboardLayout,
                audio: {output: Audio.sink, input: Audio.source, recording: Audio.microphoneRecording, error: Audio.error},
                weather: {city: Weather.city, ready: Weather.ready, temperature: Weather.temperature, error: Weather.error},
                media: {selected: Media.selectedPlayer, index: Media.playerIndex, player: Media.player?.dbusName ?? "",
                    players: Media.players.map(player => ({name: player.dbusName, identity: player.identity,
                        canPlay: player.canPlay, canPause: player.canPause, isPlaying: player.isPlaying}))},
                nightLight: {enabled: NightLight.enabled, ready: NightLight.ready, settings: NightLight.settings, error: NightLight.error},
                notifications: {count: NotificationCenter.notifications.length, unread: NotificationCenter.unread, popups: NotificationCenter.popups.length, quiet: NotificationCenter.quiet},
                tray: Tray.items.map(item => ({id: item.id, title: item.title})),
                workspaces: Compositor.visibleWorkspaces.map(item => item.address),
                panels: Theme.railScreens.map(screen => ({output: screen.name,
                    scale: Compositor.monitors.find(monitor => monitor.name === screen.name)?.scale,
                    workspaces: Compositor.visibleWorkspaces.filter(workspace => workspace.monitor === screen.name).map(workspace => workspace.address)})),
                switching: Switcher.active, selected: Switcher.selected,
                windows: Switcher.windows.map(item => ({title: item.title, appId: item.appId}))});
        }
    }
}
