import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var desktop
    RowLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: Switcher.headerHeight
        TextLabel { text: /^\d+$/.test(root.desktop.address) ? "Desktop " + root.desktop.address : root.desktop.address.replace("special:", "") || "Windows"; Layout.fillWidth: true; font.pixelSize: 13 }
        TextLabel { text: root.desktop.output ? "Display " + (root.desktop.output.id + 1) : ""; font.pixelSize: 10; color: Theme.muted }
    }
    Rectangle {
        id: viewport
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: Switcher.headerHeight }
        color: "#6009090B"
        radius: 4
        clip: true
        Repeater {
            model: root.desktop.windows
            WindowTile {
                required property var modelData
                window: modelData
                readonly property var rect: Switcher.geometry(window)
                x: rect.x * viewport.width; y: rect.y * viewport.height
                width: Math.max(12, rect.width * viewport.width)
                height: Math.max(12, rect.height * viewport.height)
                z: selected ? 2 : 1
            }
        }
    }
}
