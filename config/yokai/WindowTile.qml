import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

Rectangle {
    id: root
    required property var window
    readonly property int selectionIndex: Switcher.windows.indexOf(window)
    readonly property bool selected: selectionIndex === Switcher.selected
    color: Theme.voidColor
    border.color: selected ? Theme.vermilion : Theme.border
    border.width: selected ? 2 : 1
    clip: true
    ScreencopyView {
        id: preview
        anchors.centerIn: parent
        width: Math.min(parent.width - 4, implicitWidth)
        height: Math.min(parent.height - 4, implicitHeight)
        captureSource: Desktop.opened ? root.window : null
        constraintSize: Qt.size(Math.max(1, parent.width - 4), Math.max(1, parent.height - 4))
        live: false
    }
    IconImage {
        anchors.centerIn: parent
        implicitSize: Math.max(12, Math.min(32, parent.width / 3, parent.height / 3))
        visible: !preview.hasContent
        source: Quickshell.iconPath(DesktopEntries.heuristicLookup(root.window.appId)?.icon || "application-x-executable", "application-x-executable")
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { Switcher.selected = root.selectionIndex; Switcher.commit(); }
    }
    ToolTip.visible: mouse.containsMouse
    ToolTip.delay: 600
    ToolTip.text: root.window.title || root.window.appId
}
