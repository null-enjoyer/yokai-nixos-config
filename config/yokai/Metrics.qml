pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var sample: ({})
    Process {
        running: Desktop.opened
        command: ["python3", Quickshell.shellPath("scripts/metrics.py")]
        stdout: SplitParser {
            onRead: data => {
                try { root.sample = JSON.parse(data); }
                catch (error) { console.warn("System counters:", error.message); }
            }
        }
    }
}
