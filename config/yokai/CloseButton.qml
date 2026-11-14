import QtQuick

IconButton {
    id: root
    iconName: "window-close-symbolic"
    iconColor: Theme.ivory
    implicitWidth: 28
    implicitHeight: 28
    background: Rectangle {
        color: root.hovered || root.activeFocus ? Theme.selection : "transparent"
        border.width: 1
        border.color: Theme.vermilion
    }
}
