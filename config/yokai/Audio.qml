pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var state: ({outputs: [], inputs: [], playback: [], recording: []})
    property bool pending: false
    readonly property var sink: state.outputs.find(device => device.name === state.defaultOutput) ?? null
    readonly property var source: state.inputs.find(device => device.name === state.defaultInput) ?? null
    readonly property int volume: sink?.volume ?? 0
    readonly property bool muted: sink?.muted ?? false
    readonly property int microphoneVolume: source?.volume ?? 0
    readonly property bool microphoneMuted: source?.muted ?? false
    readonly property bool microphoneRecording: state.microphoneRecording ?? false
    readonly property string error: state.error ?? ""
    readonly property alias playback: playbackStreams
    readonly property alias recording: recordingStreams

    ListModel { id: playbackStreams }
    ListModel { id: recordingStreams }
    function updateStreams(model, streams) {
        // Keep delegates alive while a volume slider is being dragged.
        for (let index = model.count - 1; index >= 0; index--) {
            if (!streams.some(stream => stream.id === model.get(index).streamId)) model.remove(index);
        }
        for (const stream of streams) {
            let index = -1;
            for (let row = 0; row < model.count; row++) {
                if (model.get(row).streamId === stream.id) { index = row; break; }
            }
            const entry = {streamId: stream.id, description: stream.description, detail: stream.detail, volume: stream.volume, muted: stream.muted};
            if (index < 0) model.append(entry);
            else model.set(index, entry);
        }
    }

    function setVolume(kind, device, percent) {
        if (device) Quickshell.execDetached(["pactl", "set-" + kind + "-volume", String(device.id), Math.round(Math.max(0, Math.min(100, percent))) + "%"]);
    }
    function toggleMute(kind, device) {
        if (device) Quickshell.execDetached(["pactl", "set-" + kind + "-mute", String(device.id), "toggle"]);
    }
    function selectDevice(direction, device) {
        if (device) Quickshell.execDetached(["pactl", "set-default-" + (direction === "output" ? "sink" : "source"), device.name]);
    }
    function refresh() { pending = true; refreshTimer.start(); }
    Component.onCompleted: refresh()
    Timer {
        id: refreshTimer
        interval: 60
        onTriggered: if (!snapshot.running) { root.pending = false; snapshot.running = true; }
    }
    Process {
        id: snapshot
        command: ["python3", Quickshell.shellPath("scripts/audio.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.state = JSON.parse(text);
                    root.updateStreams(playbackStreams, root.state.playback);
                    root.updateStreams(recordingStreams, root.state.recording);
                }
                catch (error) { console.warn("Audio snapshot:", error.message); }
            }
        }
        onExited: if (root.pending) refreshTimer.restart()
    }
    Process {
        id: events
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            onRead: data => { if (/ on (sink|source|server)/.test(data)) root.refresh(); }
        }
        onStarted: root.refresh()
    }
    Timer {
        interval: 2000
        repeat: true
        running: !events.running || root.error !== ""
        onTriggered: {
            if (!events.running) events.running = true;
            root.refresh();
        }
    }
}
