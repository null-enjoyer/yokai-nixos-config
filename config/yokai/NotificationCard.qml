import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

Rectangle {
    id: root
    required property var notification
    implicitHeight: content.implicitHeight + 32
    radius: 8
    color: Theme.surface
    border.width: 1
    border.color: notification.urgency === NotificationUrgency.Critical ? Theme.vermilion : Theme.border
    Rectangle { x: 0; y: 18; width: 2; height: 26; color: Theme.vermilion }
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 16; topMargin: 16 }
        spacing: 10
        RowLayout {
            IconImage {
                implicitSize: 20
                source: root.notification.image || (root.notification.appIcon.startsWith("/") || root.notification.appIcon.includes(":/") ? root.notification.appIcon : Quickshell.iconPath(root.notification.appIcon, "preferences-system-notifications-symbolic"))
            }
            TextLabel { Layout.fillWidth: true; text: root.notification.appName || "Notification"; color: Theme.muted; font.pixelSize: 11 }
            CloseButton { onClicked: NotificationCenter.dismiss(root.notification) }
        }
        Item {
            Layout.fillWidth: true; implicitHeight: message.implicitHeight
            ColumnLayout {
                id: message
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: 6
                TextLabel { Layout.fillWidth: true; text: root.notification.summary; font.pixelSize: 14; font.weight: Font.Medium; wrapMode: Text.WordWrap; maximumLineCount: 2 }
                TextLabel { Layout.fillWidth: true; visible: text !== ""; text: root.notification.body; font.pixelSize: 12; color: Theme.muted; wrapMode: Text.WordWrap; maximumLineCount: 4 }
            }
            MouseArea { anchors.fill: parent; onClicked: NotificationCenter.activate(root.notification) }
        }
        RowLayout {
            visible: actions.count > 0
            Layout.fillWidth: true
            Repeater {
                id: actions
                model: root.notification.actions.filter(action => action.identifier !== "default")
                YokaiButton { required property var modelData; text: modelData.text; implicitHeight: 30; onClicked: modelData.invoke() }
            }
        }
    }
}
