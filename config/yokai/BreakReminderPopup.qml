import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: root
    visible: BreakReminder.showing
    screen: BreakReminder.screen ?? Quickshell.screens[0]
    implicitWidth: 430
    implicitHeight: 220
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yokai-break-reminder"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    FrostPanel {
        anchors.fill: parent
        color: Theme.surface
        ColumnLayout {
            anchors.fill: parent
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                IconImage { implicitSize: 30; source: Qt.resolvedUrl("assets/stretch-symbolic.svg") }
                TextLabel { text: "Time to move"; font.pixelSize: 23; Layout.fillWidth: true }
                CloseButton { onClicked: BreakReminder.dismiss() }
            }
            TextLabel {
                text: "Stand up, stretch, or take a short walk."
                Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone
                font.pixelSize: 14; color: Theme.muted
            }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                YokaiButton { text: "Done"; highlighted: true; onClicked: BreakReminder.dismiss() }
                YokaiButton { text: "In 5 minutes"; onClicked: BreakReminder.dismiss(5) }
            }
        }
    }
}
