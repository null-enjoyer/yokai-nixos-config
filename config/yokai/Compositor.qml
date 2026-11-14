pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var monitors: []
    property var workspaces: []
    property var clients: []
    property string keyboardLayout: ""
    readonly property string keyboardLayoutShort: keyboardLayout.includes("Russian") ? "RU" : keyboardLayout.includes("English") ? "EN" : keyboardLayout.slice(0, 2).toUpperCase()
    property bool pending: false
    property bool connected: events.connected
    readonly property var visibleWorkspaces: workspaces
        .filter(item => !item.special && (item.windows > 0 || Theme.showActiveEmpty && item.focused))
        .sort((a, b) => a.id - b.id)
    function clientByAddress(address) {
        const identity = String(address).replace(/^0x/, "");
        if (!identity || identity === "0") return null;
        return clients.find(client => client.address.replace(/^0x/, "") === identity) ?? null;
    }
    function focusWorkspace(address) {
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + JSON.stringify(address) + " })"]);
    }
    function refresh() { pending = true; refreshTimer.start(); }
    Component.onCompleted: refresh()
    Timer {
        id: refreshTimer
        interval: 70
        onTriggered: if (!snapshot.running) { root.pending = false; snapshot.running = true; }
    }
    Process {
        id: snapshot
        command: ["python3", Quickshell.shellPath("scripts/compositor.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.monitors = value.monitors;
                    root.workspaces = value.workspaces;
                    root.clients = value.clients;
                    root.keyboardLayout = value.keyboardLayout;
                } catch (error) { console.warn("Hyprland snapshot:", error.message); }
            }
        }
        onExited: if (root.pending) refreshTimer.restart()
    }
    Socket {
        id: events
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket2.sock"
        connected: true
        parser: SplitParser {
            onRead: data => {
                const event = data.split(">>")[0];
                if (event === "activelayout") {
                    // Query the main keyboard: other devices can have independent layouts.
                    root.refresh();
                    return;
                }
                if (event === "custom") {
                    const action = data.slice(data.indexOf(">>") + 2).trim();
                    if (action === "yokai:search") Desktop.search();
                    else if (action === "yokai:clipboard") Desktop.clipboard();
                    else if (action === "yokai:lock") LockScreen.lock();
                    else if (action === "yokai:next") Switcher.step(1);
                    else if (action === "yokai:previous") Switcher.step(-1);
                    else if (action === "yokai:finish" && Desktop.mode === "windows") Switcher.commit();
                    return;
                }
                // Focus can change between outputs without a window event. Title updates
                // do not affect workspace occupancy and should not trigger snapshots.
                if (/^(workspace|focusedmon|monitor|createworkspace|destroyworkspace|moveworkspace|openwindow|closewindow|movewindow|activewindow|activespecial|renameworkspace)/.test(event)) root.refresh();
            }
        }
        onConnectedChanged: if (connected) root.refresh()
    }
    Timer { interval: 2000; repeat: true; running: !events.connected; onTriggered: events.connected = true }
}
