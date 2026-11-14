pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string interfaceName: ""
    property int period: 900
    property var snapshot: ({})
    property string error: ""
    property int generation: 0
    property int readingGeneration: -1
    property bool pending: false
    property double requestedAt: Date.now() / 1000
    readonly property bool loading: pending || reader.running && readingGeneration === generation
    readonly property bool matchesSelection: snapshot.interface === interfaceName && snapshot.period === period
    readonly property var points: matchesSelection ? snapshot.points ?? [] : []
    readonly property bool hasCoverage: matchesSelection && (points.some(point => valid(point.download) || valid(point.upload))
        || valid(snapshot.latest?.download) || valid(snapshot.latest?.upload))
    readonly property var latest: matchesSelection && error === "" ? snapshot.latest : null
    readonly property var totals: matchesSelection && hasCoverage ? snapshot.totals : null
    readonly property double windowStart: matchesSelection ? snapshot.start : requestedAt - period
    readonly property double windowEnd: matchesSelection ? snapshot.end : requestedAt
    readonly property double observedSince: matchesSelection && valid(snapshot.observedSince) ? snapshot.observedSince : 0

    function valid(value) { return typeof value === "number" && isFinite(value) && value >= 0; }
    function refresh() {
        generation++;
        requestedAt = Date.now() / 1000;
        error = "";
        pending = Desktop.opened && interfaceName !== "";
        if (reader.running) reader.signal(15);
        else startRead();
    }
    function startRead() {
        if (!pending || !Desktop.opened) return;
        pending = false;
        readingGeneration = generation;
        reader.command = ["python3", Quickshell.shellPath("scripts/network_history.py"), "read", "--interface", interfaceName, "--period", String(period)];
        reader.running = true;
    }
    function receive(text) {
        if (readingGeneration !== generation || !Desktop.opened) return;
        try {
            const value = JSON.parse(text);
            if (value.interface !== interfaceName || value.period !== period) return;
            if (!Array.isArray(value.points) || !valid(value.start) || !valid(value.end) || value.end <= value.start)
                throw new Error("Invalid network history response");
            snapshot = value;
            error = value.error ?? "";
        } catch (exception) {
            error = "Network history could not be read.";
        }
    }
    onInterfaceNameChanged: refresh()
    onPeriodChanged: refresh()
    Connections { target: Desktop; function onOpenedChanged() { root.refresh(); } }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: root.receive(text) }
        onExited: (exitCode, exitStatus) => {
            if (root.readingGeneration === root.generation && Desktop.opened && (exitCode !== 0 || exitStatus !== 0))
                root.error = "Network history could not be read.";
            if (root.pending) nextRead.restart();
        }
    }
    Timer { id: nextRead; interval: 0; onTriggered: root.startRead() }
    Timer { interval: 5000; repeat: true; running: Desktop.opened && root.interfaceName !== ""; onTriggered: if (!reader.running) root.refresh() }
}
