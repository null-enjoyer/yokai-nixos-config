import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: root
    readonly property real naturalHeight: 120 + Math.min(480, NotificationCenter.notifications.length * 150)
    signal closeRequested()
    spacing: 14
    RowLayout {
        Layout.fillWidth: true
        TextLabel { text: "Notifications"; font.pixelSize: 16; Layout.fillWidth: true }
        CloseButton { onClicked: root.closeRequested() }
    }
    RowLayout {
        Layout.fillWidth: true
        YokaiButton { text: "Do not disturb"; highlighted: NotificationCenter.quiet; onClicked: NotificationCenter.quiet = !NotificationCenter.quiet }
        Item { Layout.fillWidth: true }
        YokaiButton { text: "Clear all"; enabled: NotificationCenter.notifications.length > 0; onClicked: NotificationCenter.clear() }
    }
    ListView {
        id: history
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true; spacing: 10
        model: NotificationCenter.notifications
        delegate: NotificationCard { required property var modelData; width: history.width; notification: modelData }
        ScrollBar.vertical: ScrollBar {}
        TextLabel { anchors.centerIn: parent; visible: history.count === 0; text: "No notifications"; color: Theme.muted; font.pixelSize: 13 }
    }
}
