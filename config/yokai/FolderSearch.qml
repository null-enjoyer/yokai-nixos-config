pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property string query: ""
    property var results: []
    property string error: ""
    readonly property bool busy: job.running || debounce.running
    function refresh() {
        debounce.restart();
    }
    onQueryChanged: if (Desktop.mode === "folders") refresh()
    Connections { target: Desktop; function onModeChanged() { if (Desktop.mode === "folders") root.refresh(); else { debounce.stop(); job.running = false; } } }
    Timer {
        id: debounce
        interval: 160
        onTriggered: {
            job.running = false;
            root.error = "";
            job.command = ["python3", Quickshell.shellPath("scripts/folder-search.py"), root.query, ...Theme.folderRoots];
            job.running = true;
        }
    }
    Process {
        id: job
        stdout: StdioCollector {
            onStreamFinished: {
                if (Desktop.mode !== "folders") return;
                try {
                    const value = JSON.parse(text);
                    root.results = value.folders;
                    root.error = value.error ?? "";
                } catch (error) { if (text.trim()) root.error = "Could not read folders"; }
            }
        }
    }
}
