import QtQuick

Rectangle {
    id: root
    property real padding: 22
    default property alias contents: contentArea.data
    color: Qt.rgba(Theme.elevated.r, Theme.elevated.g, Theme.elevated.b, .66)
    border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, .9)
    border.width: 1
    radius: 8

    // Blank space inside a panel must not dismiss the fullscreen overlay.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
