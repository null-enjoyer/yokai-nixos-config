pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var entries: []
    property bool paused: false
    property bool ready: false
    property string error: ""
    property string signature: ""
    property bool refreshPending: false
    property var actionResponse: null
    property string actionName: ""
    property bool pasteAfterCopy: false
    property var pasteTarget: null
    readonly property bool busy: action.running || pasteDelay.running || paste.running
    readonly property string executable: Quickshell.env("YOKAI_CLIPBOARD_EXEC") || "python3"
    function command(args) {
        const prefix = Quickshell.env("YOKAI_CLIPBOARD_EXEC") ? [executable] : [executable, Quickshell.shellPath("scripts/clipboard.py")];
        return prefix.concat(args);
    }
    function refresh() {
        if (Desktop.mode !== "clipboard") return;
        if (reader.running || action.running) { refreshPending = true; return; }
        refreshPending = false;
        reader.running = true;
    }
    function change(name, id = "") {
        if (busy) return;
        error = "";
        actionName = name;
        actionResponse = null;
        action.command = command(id ? [name, id] : [name]);
        action.running = true;
    }
    function copy(id, insert = false) {
        if (busy) return;
        pasteAfterCopy = insert;
        pasteTarget = Desktop.clipboardTarget;
        change("copy", id);
    }
    Connections {
        target: Desktop
        function onModeChanged() { if (Desktop.mode === "clipboard") root.refresh(); }
    }
    Timer { interval: 1500; running: Desktop.mode === "clipboard"; repeat: true; onTriggered: root.refresh() }
    Timer { id: refreshSoon; interval: 0; onTriggered: root.refresh() }
    Process {
        id: reader
        command: root.command(["list"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (!Array.isArray(value.entries)) throw new Error("Invalid clipboard response");
                    if (root.signature !== text) {
                        root.signature = text;
                        root.entries = value.entries;
                    }
                    root.paused = value.paused;
                    root.ready = true;
                    if (root.error === "Could not read clipboard history") root.error = "";
                } catch (exception) { root.ready = false; root.error = "Could not read clipboard history"; }
            }
        }
        onExited: code => {
            if (code !== 0) { root.ready = false; root.error = "Could not read clipboard history"; }
            if (root.refreshPending) refreshSoon.restart();
        }
    }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.actionResponse = JSON.parse(text); }
                catch (exception) { root.actionResponse = null; }
            }
        }
        onExited: code => {
            if (code !== 0 || root.actionResponse?.ok !== true) {
                root.error = "Clipboard action failed. Try again.";
                root.pasteAfterCopy = false;
            } else if (root.actionName === "copy") {
                Desktop.close();
                if (root.pasteAfterCopy && root.pasteTarget?.address) pasteDelay.restart();
            }
            root.refreshPending = true;
            refreshSoon.restart();
        }
    }
    Timer {
        id: pasteDelay
        interval: 150
        onTriggered: {
            const target = root.pasteTarget;
            root.pasteAfterCopy = false;
            if (!target?.address || LockScreen.locked || Desktop.opened) return;
            const terminal = /ghostty|kitty|alacritty|foot|wezterm|org\.gnome\.Terminal|konsole/i.test(target.appId);
            const mods = terminal ? "CTRL SHIFT" : "CTRL";
            const expression = "hl.dsp.send_shortcut({mods=" + JSON.stringify(mods)
                + ",key=\"v\",window=" + JSON.stringify("address:" + target.address) + "})";
            paste.command = ["hyprctl", "dispatch", expression];
            paste.running = true;
        }
    }
    Process {
        id: paste
        onExited: code => {
            if (code !== 0) Quickshell.execDetached(["notify-send", "Clipboard", "Copied. Press your application's paste shortcut to insert it."]);
        }
    }
}
