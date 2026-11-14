pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

YokaiButton {
    id: root
    property string iconName: ""
    property string trailingText: ""
    property bool selected: false
    property bool tab: false
    implicitHeight: 38
    Accessible.name: text
    background: Rectangle {
        radius: 4
        color: root.hovered || root.down ? "#12FFFFFF" : "transparent"
        border.width: 1
        border.color: !root.enabled ? Theme.border : root.highlighted || root.activeFocus
            ? Theme.vermilion : root.hovered ? Theme.muted : Qt.rgba(Theme.ivory.r, Theme.ivory.g, Theme.ivory.b, .22)
        Rectangle {
            visible: root.selected
            color: Theme.vermilion
            x: root.tab ? 1 : 0
            y: root.tab ? parent.height - height : 5
            width: root.tab ? parent.width - 2 : 2
            height: root.tab ? 2 : parent.height - 10
        }
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
    contentItem: RowLayout {
        spacing: 10
        IconImage {
            visible: root.iconName !== ""
            implicitSize: 17
            source: Quickshell.iconPath(root.iconName, "application-x-executable-symbolic")
            opacity: root.enabled ? 1 : .45
            layer.enabled: true
            layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: Theme.ivory }
        }
        TextLabel {
            Layout.fillWidth: true
            text: root.text
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            color: root.enabled ? Theme.ivory : Theme.muted
        }
        TextLabel {
            visible: root.trailingText !== ""
            text: root.trailingText
            font.pixelSize: 13
            color: Theme.muted
            font.family: "JetBrains Mono"
        }
    }
}
