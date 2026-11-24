import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

PanelMenu {
    id: root
    objectName: "yokai-break-reminder-menu"
    heading: "Move reminders"
    fitContents: true
    function loadSettings() {
        minutes.text = String(BreakReminder.settings.intervalMinutes);
        apps.text = BreakReminder.settings.excludedApps.join(", ");
    }
    function saveSettings() {
        if (!minutes.acceptableInput) return;
        BreakReminder.configure({intervalMinutes: Number(minutes.text),
            excludedApps: apps.text.split(",").map(app => app.trim()).filter(Boolean)});
    }
    onVisibleChanged: if (visible) loadSettings()
    Connections {
        target: BreakReminder
        function onSettingsChanged() {
            if (root.visible && !minutes.activeFocus && !apps.activeFocus) root.loadSettings();
        }
    }
    RowLayout {
        Layout.fillWidth: true
        TextLabel {
            Layout.fillWidth: true
            font.pixelSize: 13; color: Theme.muted
            text: !BreakReminder.ready ? "Loading…" : !BreakReminder.enabled ? "Off"
                : BreakReminder.blockingApp ? "Paused for " + BreakReminder.blockingApp
                : BreakReminder.blocked ? "Paused" : "Next break in " + BreakReminder.remainingMinutes + " min"
        }
        YokaiButton {
            text: BreakReminder.enabled ? "Turn off" : "Turn on"
            enabled: BreakReminder.ready && !BreakReminder.busy
            onClicked: BreakReminder.toggle()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        TextLabel { text: "Remind every"; Layout.fillWidth: true; font.pixelSize: 13 }
        TextField {
            id: minutes
            Layout.preferredWidth: 76; implicitHeight: 38
            text: String(BreakReminder.settings.intervalMinutes)
            color: Theme.ivory; font.pixelSize: 13
            leftPadding: 10; rightPadding: 10
            validator: IntValidator { bottom: 1; top: 1440 }
            background: Rectangle { color: Theme.voidColor; radius: 4; border.color: minutes.activeFocus ? Theme.vermilion : Theme.border }
            onAccepted: root.saveSettings()
        }
        TextLabel { text: "min"; color: Theme.muted; font.pixelSize: 12 }
    }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 8
        TextLabel { text: "Pause while these apps are open"; font.pixelSize: 13 }
        TextField {
            id: apps
            Layout.fillWidth: true; implicitHeight: 38
            text: BreakReminder.settings.excludedApps.join(", ")
            placeholderText: "Application classes, separated by commas"
            color: Theme.ivory; placeholderTextColor: Theme.muted; font.pixelSize: 12
            leftPadding: 10; rightPadding: 10
            background: Rectangle { color: Theme.voidColor; radius: 4; border.color: apps.activeFocus ? Theme.vermilion : Theme.border }
            onAccepted: root.saveSettings()
        }
        TextLabel {
            text: "Use * for a wildcard. A new interval starts when the app closes."
            Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone
            font.pixelSize: 11; color: Theme.muted
        }
        YokaiButton {
            text: BreakReminder.currentApp ? "Add " + BreakReminder.currentApp : "No focused app"
            enabled: BreakReminder.ready && BreakReminder.currentApp !== ""
            Layout.maximumWidth: parent.width
            onClicked: {
                const entries = apps.text.split(",").map(app => app.trim()).filter(Boolean);
                if (!entries.some(app => app.toLowerCase() === BreakReminder.currentApp.toLowerCase()))
                    entries.push(BreakReminder.currentApp);
                apps.text = entries.join(", ");
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        YokaiButton {
            text: "Save settings"
            enabled: BreakReminder.ready && !BreakReminder.busy && minutes.acceptableInput
            highlighted: true
            onClicked: root.saveSettings()
        }
        YokaiButton {
            text: "Preview"
            enabled: BreakReminder.enabled && !BreakReminder.blocked
            onClicked: { root.closeReveal(); BreakReminder.preview(); }
        }
    }
    TextLabel {
        text: BreakReminder.error
        visible: text !== ""
        Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone
        color: Theme.vermilion; font.pixelSize: 12
    }
    YokaiButton {
        text: "Retry"
        visible: !BreakReminder.ready && BreakReminder.error !== ""
        enabled: !BreakReminder.busy
        onClicked: BreakReminder.refresh()
    }
}
