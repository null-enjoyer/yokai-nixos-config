import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    visible: Desktop.opened
    screen: Desktop.screen
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yokai-control"
    WlrLayershell.keyboardFocus: visible && !BrowserSearch.releasingKeyboard && !Desktop.screenshotActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Above the blur alpha threshold so the entire translucent backdrop blurs.
    color: "#4009090B"
    readonly property real edgeMargin: 64
    readonly property real panelAreaWidth: Math.max(0, width - edgeMargin * 2)
    readonly property real panelHeight: Math.max(200, height - 192)
    readonly property real systemWidth: Math.min(620, Math.max(360, panelAreaWidth * .32))
    readonly property real workspaceWidth: systemWidth
    readonly property real searchWidth: Math.min(660, Math.max(260,
        panelAreaWidth - systemWidth * 2 - 64))
    Item {
        id: keyboard
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { Desktop.close(); event.accepted = true; }
            else if (Desktop.mode === "windows") {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    Switcher.step(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true;
                } else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
                    const directions = {}; directions[Qt.Key_Left] = "left"; directions[Qt.Key_Right] = "right"; directions[Qt.Key_Up] = "up"; directions[Qt.Key_Down] = "down";
                    Switcher.move(directions[event.key]); event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { Switcher.commit(); event.accepted = true; }
            }
        }
        Keys.onReleased: event => {
            if (Desktop.mode === "windows" && (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)) { Switcher.commit(); event.accepted = true; }
        }
        MouseArea { anchors.fill: parent; onClicked: Desktop.close() }
        RowLayout {
            x: root.edgeMargin
            y: 48
            height: 28
            spacing: 8
            TextLabel { text: "神域"; font.family: "Noto Sans CJK JP"; color: Theme.vermilion; font.pixelSize: 13 }
            TextLabel { text: "YŌKAI"; font.pixelSize: 18; font.weight: Font.Medium }
        }
        FrostPanel {
            readonly property int desktopCount: Switcher.desktops.length
            width: root.workspaceWidth
            height: Math.min(root.panelHeight, Math.max(180,
                82 + desktopCount * Math.ceil(Switcher.previewHeight + Switcher.headerHeight)
                    + Math.max(0, desktopCount - 1) * Switcher.previewRowGap))
            anchors.left: parent.left
            anchors.leftMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                TextLabel { text: "Workspaces"; font.pixelSize: 18; font.weight: Font.Medium }
                WorkspaceOverview { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
        FrostPanel {
            width: root.searchWidth
            height: Math.min(Desktop.mode === "clipboard" ? 720 : 530, root.panelHeight)
            anchors.centerIn: parent
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                TextLabel { text: Desktop.mode === "clipboard" ? "Clipboard" : "Search"; font.pixelSize: 18; font.weight: Font.Medium }
                SearchPane { Layout.fillWidth: true; Layout.fillHeight: true; onFocusWindows: keyboard.forceActiveFocus() }
            }
        }
        FrostPanel {
            width: root.systemWidth
            height: Math.min(root.panelHeight, systemStatus.implicitHeight + 82)
            anchors.right: parent.right
            anchors.rightMargin: root.edgeMargin
            anchors.verticalCenter: parent.verticalCenter
            ColumnLayout {
                anchors.fill: parent
                spacing: 16
                TextLabel { text: "System"; font.pixelSize: 18; font.weight: Font.Medium }
                SystemStatus { id: systemStatus; Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
        CloseButton {
            anchors { top: parent.top; right: parent.right; margins: 24 }
            tooltip: "Close"
            onClicked: Desktop.close()
        }
    }
}
