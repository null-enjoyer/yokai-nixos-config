import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property bool joined: false
    property real horizontalPadding: 4
    default property alias contents: body.data
    implicitHeight: body.implicitHeight + 12
    color: Theme.surface
    radius: 8
    topRightRadius: joined ? 0 : radius
    bottomRightRadius: joined ? 0 : radius
    border.width: 1
    border.color: Theme.border
    data: [
        Rectangle {
            anchors.right: parent.right
            y: 0
            width: 2; height: parent.height
            color: Theme.surface
            visible: root.joined
        },
        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors { leftMargin: root.horizontalPadding; rightMargin: root.horizontalPadding; topMargin: 6; bottomMargin: 6 }
            spacing: 4
        }
    ]
}
