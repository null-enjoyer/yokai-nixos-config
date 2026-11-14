pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool active: false
    property var snapshot: ({})
    property double nextCheckAt: 0
    readonly property string city: snapshot.city ?? ""
    readonly property bool ready: snapshot.ready ?? false
    readonly property bool busy: process.running
    readonly property bool stale: snapshot.stale ?? false
    readonly property string error: snapshot.error ?? ""
    readonly property real temperature: snapshot.temperature ?? 0
    readonly property real feelsLike: snapshot.feelsLike ?? 0
    readonly property string condition: snapshot.condition ?? ""
    readonly property string iconName: snapshot.iconName ?? "weather-overcast"
    readonly property real high: snapshot.high ?? 0
    readonly property real low: snapshot.low ?? 0
    readonly property double updatedAt: snapshot.updatedAt ?? 0
    readonly property var forecast: snapshot.forecast ?? []

    function collect(text) {
        try {
            const value = JSON.parse(text);
            snapshot = value;
            nextCheckAt = value.nextCheckAt ?? 0;
        } catch (error) {
            snapshot = Object.assign({}, snapshot, {error: "Weather response could not be read."});
        }
    }
    function refresh() {
        if (busy || Date.now() / 1000 < nextCheckAt) return;
        nextCheckAt = Date.now() / 1000 + 300;
        process.command = ["python3", Quickshell.shellPath("scripts/weather.py")];
        process.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: {
        process.command = ["python3", Quickshell.shellPath("scripts/weather.py"), "--cached"];
        process.running = true;
    }
    Process {
        id: process
        stdout: SplitParser { onRead: data => root.collect(data) }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) {
                root.snapshot = Object.assign({}, root.snapshot, {error: "Weather helper could not run."});
                root.nextCheckAt = Date.now() / 1000 + 300;
            }
            if (root.active) root.refresh();
        }
    }
    Timer {
        interval: 60000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }
}
