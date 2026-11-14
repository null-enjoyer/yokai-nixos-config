import QtQuick
import QtQuick.Controls

Slider {
    id: root
    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: root.availableWidth
        implicitHeight: 3
        height: 3
        radius: 2
        color: Theme.border
        Rectangle { width: root.visualPosition * parent.width; height: parent.height; radius: 2; color: Theme.vermilion }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        implicitWidth: 12; implicitHeight: 12
        radius: 6
        color: Theme.ivory
        border.color: root.activeFocus ? Theme.vermilion : Theme.border
    }
}
