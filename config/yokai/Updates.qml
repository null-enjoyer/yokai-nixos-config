pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "UpdateStatus.js" as UpdateStatus

Singleton {
    id: root
    property bool active: false
    readonly property bool enabled: Quickshell.env("YOKAI_UPDATES_ENABLED") === "1"
    readonly property string executable: Quickshell.env("YOKAI_UPDATES_EXEC") || ""
    property var state: ({})
    property bool connected: false
    property string transportError: enabled && !executable ? "The update service is not configured." : ""
    property string requestError: ""
    property int revision: 0
    property double now: Date.now()
    readonly property bool running: Boolean(state.busy) || action.running
    readonly property bool hasUpdates: Boolean(state.available)
    readonly property bool ready: Boolean(state.prepared?.ready)
    readonly property var automaticFailure: UpdateStatus.currentAutomaticFailure(automations, generations)
    readonly property bool failed: Boolean(error) || automaticFailure !== null
    readonly property string checkError: Object.keys(state.checkErrors || {}).map(scope => "Check · " + scope + ": " + state.checkErrors[scope]).join("\n")
    readonly property string automaticError: automaticFailure ? (automaticFailure.label || "Automatic update") + ": " + (automaticFailure.error || "Failed") : ""
    readonly property string error: [requestError, transportError, state.error, checkError, automaticError].filter(value => Boolean(value)).join("\n")
    readonly property var changes: state.changes || ({system: [], tools: [], flatpak: []})
    readonly property var history: state.history || []
    readonly property var automations: state.automations || []
    readonly property var generations: state.generations || []
    readonly property string latestId: state.operationId || history[0]?.id || ""
    readonly property string title: !enabled ? "Updates are disabled" : !connected ? "Updates unavailable" : state.busy ? stageLabel : ready ? "Ready to apply" : failed ? "Update needs attention" : state.restartRequired ? "Restart required" : state.pendingBoot ? "Ready for next boot" : hasUpdates ? "Updates available" : state.lastChecked && state.lastCheckSuccessful ? "Up to date" : state.lastChecked ? "Not fully checked" : "Not checked yet"
    readonly property string stageLabel: state.stage || ({checking: "Checking updates", preparing: "Preparing update", applying: "Applying update", booting: "Preparing next boot", "updating-flatpak": "Updating Flatpak applications", "rolling-back": "Restoring system generation"})[state.status] || "Working"
    readonly property string elapsed: {
        if (!state.busy || !state.startedAt) return "";
        const seconds = Math.max(0, Math.floor((now - Date.parse(state.startedAt)) / 1000));
        return seconds < 60 ? seconds + "s elapsed" : Math.floor(seconds / 60) + "m " + seconds % 60 + "s elapsed";
    }
    property string detailId: ""
    property string detailLog: ""
    property string detailError: ""
    property bool detailsActive: false
    property int detailRevision: 0
    property string copyText: ""
    readonly property bool canAct: enabled && executable !== "" && connected && !running
    readonly property bool loadingDetails: details.running

    function formatTime(value) {
        if (!value) return "Not available";
        const date = new Date(value);
        return isNaN(date.getTime()) ? String(value) : Qt.formatDateTime(date, "ddd d MMM, HH:mm");
    }
    function refresh() {
        if (!enabled || !executable || snapshot.running || action.running) return;
        snapshot.requestRevision = revision;
        snapshot.running = true;
    }
    function acceptSnapshot(value) {
        if (!value || typeof value.status !== "string") throw new Error("Invalid update service response");
        state = value;
        connected = true;
        transportError = "";
    }
    function run(actionName, generation) {
        if (!canAct || !["check", "prepare", "apply", "boot", "flatpak", "retry", "rollback"].includes(actionName)) return;
        const command = [executable, "action", actionName];
        if (actionName === "rollback" && generation !== undefined) {
            if (!Number.isInteger(generation) || generation < 1) return;
            command.push("--generation", String(generation));
        }
        revision++;
        requestError = "";
        action.command = command;
        action.running = true;
    }
    function showDetails(id) {
        if (detailId !== id) {
            detailRevision++;
            detailId = id;
            detailLog = "";
            detailError = "";
        }
        refreshDetails();
    }
    function refreshDetails() {
        if (!enabled || !executable || !detailId || details.running) return;
        details.requestRevision = detailRevision;
        details.command = [executable, "details", "--id", detailId];
        details.running = true;
    }
    function copyError() {
        if (clipboard.running) return;
        copyText = error || detailError || detailLog;
        if (!copyText) return;
        clipboard.stdinEnabled = true;
        clipboard.running = true;
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()
    Timer { interval: root.active ? 2000 : 30000; repeat: true; running: root.enabled; onTriggered: { root.refresh(); if (root.active && root.detailsActive) root.refreshDetails(); } }
    Timer { interval: 1000; repeat: true; running: root.active && root.running; onTriggered: root.now = Date.now() }
    Process {
        id: snapshot
        property int requestRevision: 0
        command: [root.executable, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (snapshot.requestRevision !== root.revision) return;
                try { root.acceptSnapshot(JSON.parse(text)); }
                catch (error) { root.connected = false; root.transportError = "Cannot read update service status."; }
            }
        }
        onExited: (code, status) => {
            if (requestRevision !== root.revision) return;
            if (code !== 0 || status !== 0) { root.connected = false; root.transportError = "Update service is unavailable."; }
        }
    }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    if (!value.ok) root.requestError = value.error || "The update request was rejected.";
                    if (value.snapshot) root.acceptSnapshot(value.snapshot);
                } catch (error) { root.requestError = "Cannot read the update request response."; }
            }
        }
        onExited: (code, status) => {
            if ((code !== 0 || status !== 0) && !root.requestError) root.requestError = "Could not contact the update service.";
            Qt.callLater(root.refresh);
        }
    }
    Process {
        id: details
        property int requestRevision: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (details.requestRevision !== root.detailRevision) return;
                try {
                    const value = JSON.parse(text);
                    if (value.id && value.id !== root.detailId) return;
                    root.detailLog = value.log || "";
                    root.detailError = value.ok ? "" : value.error || "Log is unavailable.";
                } catch (error) { root.detailError = "Cannot read the operation log."; }
            }
        }
        onExited: (code, status) => {
            if (requestRevision === root.detailRevision && (code !== 0 || status !== 0)) root.detailError = "Operation log is unavailable.";
            if (requestRevision !== root.detailRevision) Qt.callLater(root.refreshDetails);
        }
    }
    Process {
        id: clipboard
        command: ["wl-copy"]
        onStarted: { write(root.copyText); root.copyText = ""; stdinEnabled = false; }
    }
}
