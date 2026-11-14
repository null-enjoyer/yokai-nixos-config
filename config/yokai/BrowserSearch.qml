pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Fuzzy.js" as Fuzzy

Singleton {
    id: root
    property var results: []
    property string resultsQuery: ""
    property bool ready: false
    property string error: ""
    property string openError: ""
    property int generation: 0
    property int readingGeneration: -1
    property string readingQuery: ""
    property bool pending: false
    property int openingGeneration: -1
    property string openingQuery: ""
    property var openingCommand: []
    property var openResponse: null
    property bool opening: false
    readonly property bool releasingKeyboard: opening && openingGeneration === generation && searchActive()
    readonly property bool busy: debounce.running || pending || reader.running && readingGeneration === generation

    // Derived bindings can lag Desktop signals; handlers read the source fields.
    function searchActive() { return Desktop.mode === "apps" && Desktop.query.trim() !== ""; }
    function refresh() {
        generation++;
        debounce.stop();
        pending = false;
        results = [];
        resultsQuery = "";
        error = "";
        openError = "";
        if (beginOpen.running) {
            beginOpen.stop();
            opening = false;
            openingCommand = [];
        }
        if (reader.running) reader.signal(15);
        if (searchActive()) debounce.restart();
    }
    function startSearch() {
        if (!pending || !searchActive() || reader.running) return;
        pending = false;
        readingGeneration = generation;
        readingQuery = Desktop.query;
        reader.command = ["python3", Quickshell.shellPath("scripts/browser_bridge.py"), "search", "--queries", JSON.stringify(Fuzzy.keyboardQueries(readingQuery))];
        reader.running = true;
    }
    function receive(text) {
        if (readingGeneration !== generation || !searchActive() || readingQuery !== Desktop.query) return;
        try {
            const value = JSON.parse(text);
            if (!Array.isArray(value.results)) throw new Error("Invalid browser results");
            ready = value.ready === true;
            error = value.error ? "Browser history is unavailable." : "";
            results = value.results.filter(result => result.kind === "browser" && typeof result.id === "string"
                && typeof result.sourceId === "string" && result.sourceId !== "" && typeof result.url === "string"
                && /^https?:\/\//i.test(result.url) && typeof result.title === "string" && typeof result.score === "number" && isFinite(result.score) && result.score >= 0)
                .slice(0, 80).map(result => Object.assign({}, result, {title: result.title || result.url,
                    description: result.profileName ? result.profileName + " · " + result.url : result.url,
                    icon: "brave-browser", sourceLabel: "Brave"}));
            resultsQuery = readingQuery;
        } catch (exception) {
            error = "Browser history is unavailable.";
        }
    }
    function open(result) {
        const current = results.find(item => item.id === result?.id);
        if (opening || TelegramSearch.opening || opener.running || !searchActive() || resultsQuery !== Desktop.query || !current) return;
        openError = "";
        openingGeneration = generation;
        openingQuery = Desktop.query;
        openResponse = null;
        openingCommand = ["python3", Quickshell.shellPath("scripts/browser_bridge.py"), "open", "--source", current.sourceId, "--url", current.url];
        opening = true;
        beginOpen.restart();
    }
    function currentOpen() { return openingGeneration === generation && searchActive() && openingQuery === Desktop.query; }
    Connections {
        target: Desktop
        function onQueryChanged() { root.refresh(); }
        function onModeChanged() { root.refresh(); }
    }
    Component.onCompleted: refresh()
    Timer {
        id: debounce
        interval: 160
        onTriggered: { root.pending = true; root.startSearch(); }
    }
    Timer { id: nextSearch; interval: 0; onTriggered: root.startSearch() }
    Timer {
        id: beginOpen
        // Let the layer surface commit its released keyboard focus before opening.
        interval: 50
        onTriggered: {
            if (!root.currentOpen()) { root.opening = false; return; }
            opener.command = root.openingCommand;
            opener.running = true;
        }
    }
    Process {
        id: reader
        stdout: StdioCollector { onStreamFinished: root.receive(text) }
        onExited: (exitCode, exitStatus) => {
            if (root.readingGeneration === root.generation && root.searchActive() && (exitCode !== 0 || exitStatus !== 0))
                root.error = "Browser history is unavailable.";
            if (root.pending) nextSearch.restart();
        }
    }
    Process {
        id: opener
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.openResponse = JSON.parse(text); }
                catch (exception) { root.openResponse = null; }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.currentOpen()) {
                if (exitCode === 0 && exitStatus === 0 && root.openResponse?.ok === true) Desktop.close();
                else root.openError = "Could not open this page. Try again.";
            }
            root.opening = false;
        }
    }
}
