import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

AttachedPopup {
    id: root
    property string workspaceAddress: ""
    readonly property bool hovered: contentHover.hovered
    readonly property bool capturing: visible && !closing && !LockScreen.locked
    readonly property var workspace: Compositor.workspaces.find(item => item.address === workspaceAddress) ?? null
    readonly property var output: {
        const assigned = Compositor.monitors.find(monitor => monitor.name === workspace?.monitor);
        if (assigned) return assigned;
        const client = Compositor.clients.find(item => String(item.workspace.address ?? item.workspace.name ?? "") === workspaceAddress);
        return Compositor.monitors.find(monitor => monitor.id === client?.monitor)
            ?? Compositor.monitors.find(monitor => monitor.name === screen?.name)
            ?? null;
    }
    readonly property real outputAspect: output && output.width > 0 && output.height > 0 ? output.width / output.height : 16 / 9
    heading: /^\d+$/.test(workspaceAddress) ? "Desktop " + workspaceAddress : workspaceAddress.replace("special:", "") || "Desktop"
    dismissOnOutsideClick: false
    connected: false
    surfaceVisible: false
    implicitWidth: Math.max(1, Math.min(400, (screen?.width ?? 440) - 40, ((screen?.height ?? 800) - 32) * outputAspect))
    implicitHeight: implicitWidth / outputAspect

    ListModel { id: windowRows }

    function syncWindows() {
        if (!visible || LockScreen.locked || !workspaceAddress) {
            windowRows.clear();
            return;
        }
        const available = ToplevelManager.toplevels.values.filter(window => window.appId !== "org.quickshell"
            && window.parent === null && Switcher.desktopAddress(window) === workspaceAddress);
        // Keep the capture delegate alive when only compositor geometry changes.
        for (let index = windowRows.count - 1; index >= 0; index--) {
            if (!available.includes(windowRows.get(index).window)) windowRows.remove(index);
        }
        for (let index = 0; index < available.length; index++) {
            const window = available[index];
            let row = -1;
            for (let candidate = 0; candidate < windowRows.count; candidate++) {
                if (windowRows.get(candidate).window === window) { row = candidate; break; }
            }
            if (row < 0) windowRows.insert(index, {window: window});
            else if (row !== index) windowRows.move(row, index, 1);
        }
    }

    function activateWindow(window) {
        if (!capturing || !ToplevelManager.toplevels.values.includes(window)) return;
        closeReveal();
        window.activate();
    }

    onWorkspaceAddressChanged: syncWindows()
    onVisibleChanged: syncWindows()
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.syncWindows(); }
    }
    Connections {
        target: Compositor
        function onClientsChanged() { root.syncWindows(); }
    }
    Connections {
        target: LockScreen
        function onLockedChanged() {
            if (LockScreen.locked) root.closeReveal(true);
            root.syncWindows();
        }
    }

    Rectangle {
        id: viewport
        anchors.fill: parent
        color: Theme.voidColor
        clip: true
        HoverHandler { id: contentHover }
        Repeater {
            model: windowRows
            Rectangle {
                id: tile
                required property var window
                readonly property var rect: {
                    const clients = Compositor.clients;
                    return Switcher.geometry(window, root.output);
                }
                readonly property bool active: ToplevelManager.activeToplevel === window
                x: rect.x * viewport.width
                y: rect.y * viewport.height
                width: Math.max(1, rect.width * viewport.width)
                height: Math.max(1, rect.height * viewport.height)
                z: active ? 2 : 1
                color: Theme.elevated
                clip: true
                ScreencopyView {
                    id: preview
                    anchors.centerIn: parent
                    width: Math.min(Math.max(1, parent.width - 4), implicitWidth)
                    height: Math.min(Math.max(1, parent.height - 4), implicitHeight)
                    captureSource: root.visible && !LockScreen.locked ? tile.window : null
                    constraintSize: Qt.size(Math.max(1, parent.width - 4), Math.max(1, parent.height - 4))
                    live: root.capturing
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: Math.max(8, Math.min(32, parent.width / 3, parent.height / 3))
                    visible: !preview.hasContent
                    source: Quickshell.iconPath(DesktopEntries.heuristicLookup(tile.window.appId)?.icon || "application-x-executable", "application-x-executable")
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: tile.active || windowMouse.containsMouse ? 2 : 1
                    border.color: tile.active ? Theme.vermilion : windowMouse.containsMouse ? Theme.ivory : Theme.border
                }
                MouseArea {
                    id: windowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateWindow(tile.window)
                }
            }
        }
        TextLabel {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 32)
            visible: windowRows.count === 0
            text: "No windows on this desktop"
            color: Theme.muted
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Rectangle {
            anchors.fill: parent
            z: 1000
            color: "transparent"
            border.width: 1
            border.color: Theme.vermilion
        }
    }
}
