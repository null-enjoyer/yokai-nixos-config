pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Fuzzy.js" as Fuzzy

Singleton {
    id: root
    readonly property bool enabled: Quickshell.env("YOKAI_TELEGRAM_ENABLED") !== "0"
    property var results: []
    property string resultsQuery: ""
    property string state: "credentials"
    property bool ready: false
    property bool authBusy: false
    property string error: ""
    property string searchError: ""
    property string openError: ""
    property string qrPath: ""
    property int qrRevision: 0
    property string passwordHint: ""
    property int chatCount: 0
    property bool setupVisible: false
    property var setupScreen: null
    property int generation: 0
    property int readingGeneration: -1
    property string readingQuery: ""
    property bool pending: false
    property bool opening: false
    property int openingGeneration: -1
    property string openingQuery: ""
    property string requestPayload: ""
    property bool requestStatusReceived: false
    property string resolvePayload: ""
    property var resolveResponse: null
    property int statusGeneration: 0
    property int readingStatusGeneration: -1
    readonly property bool busy: debounce.running || pending || reader.running && readingGeneration === generation
    readonly property bool submitting: request.running || authBusy || restarter.running
    readonly property bool polling: enabled && (setupVisible || Desktop.opened)

    function helper(command) { return ["python3", Quickshell.shellPath("scripts/telegram_search.py"), command]; }
    function searchActive() { return enabled && ready && Desktop.mode === "apps" && Desktop.query.trim() !== ""; }
    function refresh() {
        generation++;
        debounce.stop();
        pending = false;
        results = [];
        resultsQuery = "";
        searchError = "";
        openError = "";
        if (reader.running) reader.signal(15);
        if (searchActive()) debounce.restart();
    }
    function startSearch() {
        if (!pending || !searchActive() || reader.running) return;
        pending = false;
        readingGeneration = generation;
        readingQuery = Desktop.query;
        reader.command = helper("search").concat(["--queries", JSON.stringify(Fuzzy.keyboardQueries(readingQuery))]);
        reader.running = true;
    }
    function receiveResults(text) {
        if (readingGeneration !== generation || !searchActive() || readingQuery !== Desktop.query) return;
        try {
            const value = JSON.parse(text);
            if (!Array.isArray(value.results)) throw new Error("Invalid Telegram results");
            searchError = value.error ? "Telegram search is unavailable." : "";
            results = value.results.filter(item => item.kind === "telegram" && typeof item.id === "string"
                && typeof item.title === "string" && typeof item.score === "number" && isFinite(item.score) && item.score >= 0)
                .slice(0, 80).map(item => Object.assign({}, item, {icon: "telegram", sourceLabel: "Telegram",
                    openable: item.openable === true,
                    description: item.openable === true ? String(item.description || "") : "No direct Desktop link"}));
            resultsQuery = readingQuery;
        } catch (exception) { searchError = "Telegram search is unavailable."; }
    }
    function applyStatus(value) {
        if (!["credentials", "phone", "qr", "code", "password", "email", "emailCode", "ready", "error"].includes(value.state)) return false;
        state = value.state;
        ready = value.ready === true;
        authBusy = value.busy === true;
        error = typeof value.error === "string" ? value.error : "";
        qrPath = typeof value.qrPath === "string" ? value.qrPath : "";
        qrRevision = Number(value.qrRevision) || 0;
        passwordHint = typeof value.passwordHint === "string" ? value.passwordHint : "";
        chatCount = Number(value.chatCount) || 0;
        return true;
    }
    function refreshStatus() {
        if (!polling || statusReader.running || request.running || restarter.running) return;
        readingStatusGeneration = statusGeneration;
        statusReader.command = helper("status");
        statusReader.running = true;
    }
    function showSetup(targetScreen) {
        if (!enabled) return;
        Desktop.close();
        Desktop.closePanelMenu();
        setupScreen = targetScreen ?? Desktop.focusedScreen();
        setupVisible = true;
        refreshStatus();
    }
    function closeSetup() { setupVisible = false; }
    function submit(value) {
        if (!enabled || request.running || authBusy || restarter.running) return false;
        error = "";
        statusGeneration++;
        requestStatusReceived = false;
        requestPayload = JSON.stringify(value) + "\n";
        request.command = helper("request");
        request.stdinEnabled = true;
        request.running = true;
        return true;
    }
    function restartIntegration() {
        if (!enabled || restarter.running || request.running) return;
        statusGeneration++;
        error = "";
        restarter.running = true;
    }
    function open(result) {
        if (opening || BrowserSearch.opening || resolver.running || !searchActive() || resultsQuery !== Desktop.query) return;
        const current = results.find(item => item.id === result?.id);
        if (!current) return;
        openError = "";
        if (!current.openable) { openError = "This chat has no direct Telegram Desktop link."; return; }
        if (!Quickshell.env("YOKAI_TELEGRAM_EXEC")) { openError = "Telegram Desktop is unavailable."; return; }
        openingGeneration = generation;
        openingQuery = Desktop.query;
        resolveResponse = null;
        resolvePayload = JSON.stringify({type: "resolve", id: current.id}) + "\n";
        resolver.command = helper("request");
        resolver.stdinEnabled = true;
        opening = true;
        resolver.running = true;
    }
    function currentOpen() { return openingGeneration === generation && searchActive() && openingQuery === Desktop.query; }
    function finishOpen(exitCode, exitStatus) {
        if (currentOpen()) {
            const uri = resolveResponse?.uri;
            if (exitCode === 0 && exitStatus === 0 && resolveResponse?.ok === true && typeof uri === "string" && /^tg:\/\//.test(uri)) {
                const command = ["systemd-run", "--user", "--collect", "--property=Type=exec", "--slice=app.slice", "--",
                    Quickshell.env("YOKAI_TELEGRAM_EXEC"), "--", uri];
                Desktop.close();
                Qt.callLater(() => Quickshell.execDetached(command));
            } else openError = typeof resolveResponse?.error === "string" ? resolveResponse.error : "Could not open this chat. Try again.";
        }
        opening = false;
        resolvePayload = "";
    }
    onReadyChanged: refresh()
    onPollingChanged: { statusGeneration++; if (polling) refreshStatus(); }
    Connections {
        target: Desktop
        function onQueryChanged() { root.refresh(); }
        function onModeChanged() { root.refresh(); }
    }
    Timer { id: debounce; interval: 160; onTriggered: { root.pending = true; root.startSearch(); } }
    Timer { id: nextSearch; interval: 0; onTriggered: root.startSearch() }
    Timer { interval: 500; repeat: true; running: root.polling; onTriggered: root.refreshStatus() }
    Timer { id: nextStatus; interval: 0; onTriggered: root.refreshStatus() }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: root.receiveResults(text) }
        onExited: (exitCode, exitStatus) => {
            if (root.readingGeneration === root.generation && root.searchActive() && (exitCode !== 0 || exitStatus !== 0))
                root.searchError = "Telegram search is unavailable.";
            if (root.pending) nextSearch.restart();
        }
    }
    Process {
        id: statusReader
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.polling || root.readingStatusGeneration !== root.statusGeneration) return;
                try { if (!root.applyStatus(JSON.parse(text))) throw new Error("Invalid Telegram status"); }
                catch (exception) { root.error = "Telegram connection is unavailable. Try again."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.polling && root.readingStatusGeneration === root.statusGeneration && (exitCode !== 0 || exitStatus !== 0)) root.error = "Telegram connection is unavailable. Try again.";
        }
    }
    Process {
        id: request
        onStarted: {
            write(root.requestPayload);
            root.requestPayload = "";
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.requestStatusReceived = root.applyStatus(JSON.parse(text));
                    if (!root.requestStatusReceived) throw new Error("Invalid Telegram status");
                }
                catch (exception) { root.error = "Telegram connection is unavailable. Try again."; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.requestPayload = "";
            if (!root.requestStatusReceived && (exitCode !== 0 || exitStatus !== 0)) root.error = "Telegram connection is unavailable. Try again.";
            nextStatus.restart();
        }
    }
    Process {
        id: resolver
        onStarted: { write(root.resolvePayload); root.resolvePayload = ""; stdinEnabled = false; }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.resolveResponse = JSON.parse(text); }
                catch (exception) { root.resolveResponse = null; }
            }
        }
        onExited: (exitCode, exitStatus) => root.finishOpen(exitCode, exitStatus)
    }
    Process {
        id: restarter
        command: ["systemctl", "--user", "restart", "yokai-telegram.service"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0) root.error = "Could not restart Telegram search. Try again.";
            else nextStatus.restart();
        }
    }
    IpcHandler {
        target: "yokai-telegram"
        function connect(): void { root.showSetup(); }
        function status(): string { return JSON.stringify({enabled: root.enabled, state: root.state, ready: root.ready, busy: root.submitting, chatCount: root.chatCount}); }
    }
}
