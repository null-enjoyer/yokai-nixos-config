pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var settings: ({temperature: 4000, schedule: true, start: "20:30", end: "07:00"})
    property bool enabled: false
    property bool ready: false
    property string error: ""
    property var pendingSettings: ({})
    property bool temperatureDrag: false
    readonly property bool busy: action.running
    function collect(text) {
        try {
            const value = JSON.parse(text);
            if (value.settings) settings = Object.assign({}, value.settings, pendingSettings);
            if (value.ready !== undefined) ready = value.ready;
            if (value.enabled !== undefined) enabled = value.enabled;
            error = value.error ?? "";
        } catch (error) { console.warn("Night light:", error.message); }
    }
    function refresh() { if (!snapshot.running && !action.running) snapshot.running = true; }
    function toggle() {
        if (busy || Object.keys(pendingSettings).length) return;
        action.command = ["python3", Quickshell.shellPath("scripts/nightlight.py"), "toggle"];
        action.running = true;
    }
    function configure(changes) {
        settings = Object.assign({}, settings, changes);
        pendingSettings = Object.assign({}, pendingSettings, changes);
        save.restart();
    }
    function previewTemperature(value) {
        const temperature = Math.round(value / 50) * 50;
        configure({temperature: temperature});
        if (enabled) Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(temperature)]);
    }
    onTemperatureDragChanged: if (!temperatureDrag && Object.keys(pendingSettings).length) save.restart()
    Component.onCompleted: refresh()
    Timer {
        id: save
        interval: 500
        onTriggered: {
            if (!Object.keys(root.pendingSettings).length) return;
            if (action.running || root.temperatureDrag) { restart(); return; }
            action.command = ["python3", Quickshell.shellPath("scripts/nightlight.py"), "configure", JSON.stringify(root.pendingSettings)];
            root.pendingSettings = ({});
            action.running = true;
        }
    }
    Process {
        id: action
        stdout: StdioCollector { onStreamFinished: root.collect(text) }
        onExited: { if (Object.keys(root.pendingSettings).length) save.restart(); else root.refresh(); }
    }
    Process {
        id: snapshot
        command: ["python3", Quickshell.shellPath("scripts/nightlight.py"), "status"]
        stdout: StdioCollector { onStreamFinished: root.collect(text) }
    }
    Timer {
        interval: Desktop.panelMenu?.heading === "Night light" ? 1500 : 10000
        running: true; repeat: true
        onTriggered: root.refresh()
    }
}
