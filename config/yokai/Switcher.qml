pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Singleton {
    id: root
    property bool active: false
    property var windows: []
    property int selected: 0
    property int previewColumns: 1
    property real previewWidth: 360
    readonly property real previewHeight: previewWidth * 9 / 16
    readonly property real previewColumnGap: 20
    readonly property real previewRowGap: 24
    readonly property real headerHeight: 30
    readonly property var selectedWindow: windows[selected] ?? null

    function client(window) { return Compositor.clientByAddress(window.HyprlandToplevel.address); }
    function desktopAddress(window) { const info = client(window); return String(info?.workspace.address ?? info?.workspace.name ?? ""); }
    function compareDesktops(a, b) {
        const normalA = /^\d+$/.test(a), normalB = /^\d+$/.test(b);
        if (normalA !== normalB) return normalA ? -1 : 1;
        return normalA ? Number(a) - Number(b) : a.localeCompare(b);
    }
    function compareWindows(a, b) {
        const desktop = compareDesktops(desktopAddress(a), desktopAddress(b));
        if (desktop) return desktop;
        const left = client(a), right = client(b);
        return (left?.at[1] ?? 0) - (right?.at[1] ?? 0)
            || (left?.at[0] ?? 0) - (right?.at[0] ?? 0)
            || a.title.localeCompare(b.title);
    }
    property var desktops: []
    readonly property alias desktopModel: desktopRows
    ListModel { id: desktopRows }
    Component {
        id: desktopFactory
        QtObject { property string address; property var output; property var windows: [] }
    }
    function sameWindows(left, right) { return left.length === right.length && left.every((window, index) => window === right[index]); }
    function syncDesktops() {
        const groups = [];
        for (const window of active ? windows : []) {
            const address = desktopAddress(window);
            let group = groups.find(group => group.address === address);
            if (!group) {
                const info = client(window);
                const output = Compositor.monitors.find(monitor => monitor.id === info?.monitor) ?? Compositor.monitors[0];
                group = {address: address, output: output, windows: []};
                groups.push(group);
            }
            group.windows.push(window);
        }
        groups.sort((a, b) => compareDesktops(a.address, b.address));
        // Preserve desktop objects and repeater delegates across IPC snapshots.
        // Recreating a tile also destroys its captured frame.
        for (let index = desktopRows.count - 1; index >= 0; index--) {
            const desktop = desktopRows.get(index).desktop;
            if (!groups.some(group => group.address === desktop.address)) {
                desktopRows.remove(index);
                desktop.destroy();
            }
        }
        for (let index = 0; index < groups.length; index++) {
            const group = groups[index];
            let row = -1;
            for (let candidate = 0; candidate < desktopRows.count; candidate++) {
                if (desktopRows.get(candidate).desktop.address === group.address) { row = candidate; break; }
            }
            let desktop;
            if (row < 0) {
                desktop = desktopFactory.createObject(root, {address: group.address, output: group.output, windows: group.windows});
                desktopRows.insert(index, {desktop: desktop});
            } else {
                desktop = desktopRows.get(row).desktop;
                if (row !== index) desktopRows.move(row, index, 1);
                desktop.output = group.output;
                if (!sameWindows(desktop.windows, group.windows)) desktop.windows = group.windows;
            }
        }
        const next = [];
        for (let row = 0; row < desktopRows.count; row++) next.push(desktopRows.get(row).desktop);
        if (!sameWindows(desktops, next)) desktops = next;
    }
    onWindowsChanged: syncDesktops()
    onActiveChanged: syncDesktops()
    Connections {
        target: Compositor
        function onClientsChanged() { root.syncDesktops(); }
        function onMonitorsChanged() { root.syncDesktops(); }
    }
    function geometry(window, outputOverride) {
        const info = client(window);
        const group = desktops.find(group => group.windows.includes(window));
        const output = outputOverride ?? group?.output;
        if (!info || !output) return {x: .08, y: .08, width: .84, height: .84};
        const width = output.width / output.scale, height = output.height / output.scale;
        return {x: (info.at[0] - output.x) / width, y: (info.at[1] - output.y) / height,
            width: info.size[0] / width, height: info.size[1] / height};
    }
    function navigationRect(window) {
        const index = desktops.findIndex(group => group.windows.includes(window));
        const rect = geometry(window);
        return {x: (index % previewColumns) * (previewWidth + previewColumnGap) + rect.x * previewWidth,
            y: Math.floor(index / previewColumns) * (previewHeight + headerHeight + previewRowGap) + headerHeight + rect.y * previewHeight,
            width: rect.width * previewWidth, height: rect.height * previewHeight};
    }
    function prepare() {
        const available = ToplevelManager.toplevels.values.filter(window => window.appId !== "org.quickshell" && window.parent === null);
        const current = ToplevelManager.activeToplevel;
        windows = available.slice().sort(compareWindows);
        selected = Math.max(0, windows.indexOf(current));
        active = true;
    }
    function step(direction) {
        if (!active || Desktop.mode !== "windows") Desktop.enterWindows();
        if (windows.length) selected = (selected + direction + windows.length) % windows.length;
    }
    function move(direction) {
        if (!selectedWindow) return;
        const origin = navigationRect(selectedWindow);
        const x = origin.x + origin.width / 2, y = origin.y + origin.height / 2;
        let best = -1, bestScore = Infinity;
        for (let index = 0; index < windows.length; index++) {
            if (index === selected) continue;
            const candidate = navigationRect(windows[index]);
            const dx = candidate.x + candidate.width / 2 - x;
            const dy = candidate.y + candidate.height / 2 - y;
            const horizontal = direction === "left" || direction === "right";
            const along = horizontal ? dx * (direction === "left" ? -1 : 1) : dy * (direction === "up" ? -1 : 1);
            if (along <= 1) continue;
            const cross = Math.abs(horizontal ? dy : dx);
            const score = along + cross * 3;
            if (score < bestScore) { bestScore = score; best = index; }
        }
        if (best >= 0) selected = best;
    }
    function commit() {
        if (!active) return;
        const window = selectedWindow;
        Desktop.close();
        if (window && ToplevelManager.toplevels.values.includes(window)) window.activate();
    }
    function cancel() { active = false; windows = []; selected = 0; }
    function reconcile() {
        if (!active) return;
        const chosen = selectedWindow;
        const available = ToplevelManager.toplevels.values;
        windows = windows.filter(window => available.includes(window));
        selected = windows.includes(chosen) ? windows.indexOf(chosen) : Math.max(0, Math.min(selected, windows.length - 1));
    }
    Variants {
        model: ToplevelManager.toplevels.values
        delegate: QtObject { required property var modelData; readonly property string address: modelData.HyprlandToplevel.address }
    }
    Connections { target: ToplevelManager.toplevels; function onValuesChanged() { root.reconcile(); } }
}
