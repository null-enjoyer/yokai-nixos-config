pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "BreakReminderLogic.js" as Logic

Singleton {
    id: root
    property var settings: ({enabled: false, intervalMinutes: 45, excludedApps: []})
    property bool ready: false
    property string error: ""
    property var screen: Desktop.focusedScreen()
    readonly property bool busy: action.running
    readonly property bool enabled: ready && settings.enabled
    readonly property string blockingApp: Logic.blockingApp(Compositor.clients, settings.excludedApps)
    readonly property bool contextReady: Compositor.connected && Compositor.monitors.length > 0
    readonly property bool paused: blockingApp !== "" || LockScreen.locked || LockScreen.state === "locking"
    readonly property bool deferred: Desktop.screenshotActive || !contextReady
    readonly property bool blocked: paused || deferred
    readonly property bool showing: enabled && !blocked && clock.shownAt > 0
    readonly property int remainingMinutes: Math.max(0, Math.ceil((clock.dueAt - clock.lastTick) / 60000))
    readonly property string currentApp: Compositor.clients.find(client => client.focusHistoryID === 0)?.class ?? ""

    PersistentProperties {
        id: clock
        reloadableId: "yokai-break-reminder-clock"
        property double dueAt: 0
        property double lastTick: 0
        property double shownAt: 0
        property int intervalMinutes: 0
        property bool wasEnabled: false
    }

    function clockValue() {
        return {dueAt: clock.dueAt, lastTick: clock.lastTick, shownAt: clock.shownAt,
            intervalMinutes: clock.intervalMinutes, enabled: clock.wasEnabled};
    }
    function setClock(value) {
        clock.dueAt = value.dueAt;
        clock.lastTick = value.lastTick;
        clock.shownAt = value.shownAt;
        clock.intervalMinutes = value.intervalMinutes;
        clock.wasEnabled = value.enabled;
    }
    function advance() {
        if (!ready) return;
        const next = Logic.tick(clockValue(), Date.now(), settings, paused, deferred);
        if (next.shownAt && !clock.shownAt) screen = Desktop.focusedScreen();
        setClock(next);
    }
    function dismiss(delayMinutes) { setClock(Logic.reset(Date.now(), settings, delayMinutes)); }
    function preview() {
        if (!enabled || blocked) return false;
        screen = Desktop.focusedScreen();
        const next = Logic.reset(Date.now(), settings);
        next.shownAt = Date.now();
        setClock(next);
        return true;
    }
    function refresh() {
        if (busy) return;
        action.command = ["python3", Quickshell.shellPath("scripts/break-reminder.py"), "status"];
        action.running = true;
    }
    function configure(changes) {
        if (!ready || busy) return;
        action.command = ["python3", Quickshell.shellPath("scripts/break-reminder.py"), "configure", JSON.stringify(changes)];
        action.running = true;
    }
    function toggle() { configure({enabled: !settings.enabled}); }
    Component.onCompleted: refresh()
    onBlockedChanged: advance()
    Timer { interval: 1000; running: root.ready; repeat: true; onTriggered: root.advance() }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.error = value.error ?? "";
                    if (value.settings) {
                        root.settings = value.settings;
                        root.ready = true;
                        root.advance();
                    }
                } catch (error) { root.error = "Could not read reminder settings"; }
            }
        }
    }
    IpcHandler {
        target: "yokai-break-reminder"
        function status(): string {
            return JSON.stringify({ready: root.ready, settings: root.settings, blocked: root.blocked,
                blockingApp: root.blockingApp, showing: root.showing, remainingMinutes: root.remainingMinutes,
                clock: root.clockValue(), screen: root.screen?.name ?? "", error: root.error});
        }
        function preview(): bool { return root.preview(); }
        function toggle(): void { root.toggle(); }
        function dismiss(): void { root.dismiss(); }
        function snooze(): void { root.dismiss(5); }
        function refresh(): void { root.refresh(); }
    }
}
