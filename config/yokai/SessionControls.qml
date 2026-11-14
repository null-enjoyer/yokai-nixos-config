import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

ColumnLayout {
    id: root
    signal actionRequested(string action)
    property string pendingAction: ""
    spacing: 12

    function activate(action, confirm) {
        if (confirm && pendingAction !== action) {
            pendingAction = action;
            confirmationTimeout.restart();
            return;
        }
        pendingAction = "";
        confirmationTimeout.stop();
        actionRequested(action);
    }
    function clearConfirmation() { pendingAction = ""; confirmationTimeout.stop(); }

    TextLabel { text: "SESSION"; font.family: "JetBrains Mono"; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted }
    GridLayout {
        Layout.fillWidth: true
        columns: 3; rowSpacing: 8; columnSpacing: 8
        Repeater {
            model: [
                { action: "lock", label: "Lock", icon: "system-lock-screen-symbolic", confirm: false },
                { action: "sleep", label: "Sleep", icon: "weather-clear-night-symbolic", confirm: false },
                { action: "logout", label: "Log out", icon: "system-log-out-symbolic", confirm: true },
                { action: "restart", label: "Restart", icon: "system-reboot-symbolic", confirm: true },
                { action: "poweroff", label: "Power off", icon: "system-shutdown-symbolic", confirm: true }
            ]
            AbstractButton {
                id: actionButton
                required property var modelData
                readonly property bool confirming: root.pendingAction === modelData.action
                Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.preferredHeight: 80
                leftPadding: 8; rightPadding: 8; topPadding: 8; bottomPadding: 8
                hoverEnabled: true
                onClicked: root.activate(modelData.action, modelData.confirm)
                background: Rectangle {
                    radius: 4
                    color: actionButton.confirming ? Theme.selection : actionButton.hovered ? Theme.elevated : Theme.voidColor
                    border.width: 1
                    border.color: actionButton.confirming || actionButton.activeFocus ? Theme.vermilion : Theme.border
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                contentItem: ColumnLayout {
                    spacing: 7
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 24
                        source: Quickshell.iconPath(actionButton.modelData.icon)
                        layer.enabled: true
                        layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: Theme.ivory }
                    }
                    TextLabel { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: (actionButton.confirming ? "Confirm\n" : "") + actionButton.modelData.label; font.pixelSize: 13; wrapMode: Text.Wrap; elide: Text.ElideNone }
                }
            }
        }
        YokaiButton { text: "Cancel"; visible: root.pendingAction !== ""; Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.preferredHeight: 80; onClicked: root.clearConfirmation() }
    }
    TextLabel {
        Layout.fillWidth: true
        visible: root.pendingAction !== ""
        text: "Click again to confirm. Unsaved work may be lost."
        color: Theme.muted; font.pixelSize: 11; wrapMode: Text.Wrap
    }
    Timer { id: confirmationTimeout; interval: 6000; onTriggered: root.pendingAction = "" }
}
