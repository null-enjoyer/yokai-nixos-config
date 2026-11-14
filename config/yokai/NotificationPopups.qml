import QtQuick
import Quickshell
import Quickshell.Wayland

Variants {
    model: Quickshell.screens
    PanelWindow {
        id: root
        required property var modelData
        readonly property var notes: NotificationCenter.popupNotifications(modelData.name)
        screen: modelData
        visible: notes.length > 0
        anchors { top: true; right: true }
        margins { top: 20; right: 20 }
        implicitWidth: 380
        implicitHeight: stack.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "yokai-notifications"
        color: "transparent"
        Column {
            id: stack
            width: parent.width; spacing: 10
            Repeater { model: root.notes; NotificationCard { required property var modelData; width: stack.width; notification: modelData } }
        }
    }
}
