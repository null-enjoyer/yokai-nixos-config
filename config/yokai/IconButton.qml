import QtQuick
import QtQuick.Effects
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

AbstractButton {
    id: root
    signal contextMenuRequested()
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.contextMenuRequested() }
    property string iconName: ""
    property url iconSource: ""
    property real iconSize: 16
    property string tooltip: ""
    property bool selected: false
    property color iconColor: "transparent"
    implicitWidth: Theme.railWidth
    implicitHeight: 32
    hoverEnabled: true
    background: Rectangle {
        color: root.selected ? Theme.selection : root.hovered || root.activeFocus ? Theme.elevated : "transparent"
        radius: 4
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: Item {
        IconImage {
            anchors.centerIn: parent; implicitSize: root.iconSize
            source: root.iconSource.toString() !== "" ? root.iconSource : Quickshell.iconPath(root.iconName, "application-x-executable-symbolic")
            layer.enabled: root.iconColor.a > 0
            layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: root.iconColor }
        }
    }
}
