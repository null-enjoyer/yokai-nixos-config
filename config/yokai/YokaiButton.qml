import QtQuick
import QtQuick.Controls

Button {
    id: root
    implicitHeight: 36
    leftPadding: 12; rightPadding: 12
    hoverEnabled: true
    background: Rectangle {
        radius: 4
        color: root.highlighted ? Theme.selection : root.hovered ? Theme.elevated : "transparent"
        border.color: root.activeFocus ? Theme.vermilion : "transparent"
    }
    contentItem: TextLabel { text: root.text; verticalAlignment: Text.AlignVCenter; color: root.enabled ? Theme.ivory : Theme.muted; font.pixelSize: 13 }
}
