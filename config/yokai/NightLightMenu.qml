import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

PanelMenu {
    id: root
    heading: "Night light"
    implicitHeight: 410
    RowLayout {
        Layout.fillWidth: true
        TextLabel { text: NightLight.enabled ? "Enabled" : "Disabled"; color: Theme.muted; font.pixelSize: 13; Layout.fillWidth: true }
        YokaiButton { text: NightLight.enabled ? "Turn off" : "Turn on"; enabled: !NightLight.busy; onClicked: NightLight.toggle() }
    }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 8
        RowLayout {
            TextLabel { text: "Color temperature"; font.pixelSize: 14; Layout.fillWidth: true }
            TextLabel { text: NightLight.settings.temperature + " K"; color: Theme.muted; font.family: "JetBrains Mono"; font.pixelSize: 12 }
        }
        YokaiSlider {
            Layout.fillWidth: true
            from: 1000; to: 6500; stepSize: 50
            value: NightLight.settings.temperature
            enabled: !NightLight.busy
            onMoved: NightLight.previewTemperature(value)
            onPressedChanged: NightLight.temperatureDrag = pressed
        }
        RowLayout {
            TextLabel { text: "Warmer"; color: Theme.muted; font.pixelSize: 11; Layout.fillWidth: true }
            TextLabel { text: "Cooler"; color: Theme.muted; font.pixelSize: 11 }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true; spacing: 10
        RowLayout {
            TextLabel { text: "Schedule"; font.pixelSize: 14; Layout.fillWidth: true }
            YokaiButton { text: NightLight.settings.schedule ? "On" : "Off"; highlighted: NightLight.settings.schedule; enabled: !NightLight.busy; onClicked: NightLight.configure({schedule: !NightLight.settings.schedule}) }
        }
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: ["start", "end"]
                ColumnLayout {
                    required property string modelData
                    Layout.fillWidth: true; spacing: 6
                    TextLabel { text: modelData === "start" ? "From" : "Until"; color: Theme.muted; font.pixelSize: 11 }
                    TextField {
                        id: timeField
                        Layout.fillWidth: true; implicitHeight: 38
                        enabled: NightLight.settings.schedule && !NightLight.busy
                        text: NightLight.settings[modelData]
                        placeholderText: "HH:MM"
                        font.family: "JetBrains Mono"; font.pixelSize: 13
                        color: Theme.ivory; placeholderTextColor: Theme.muted
                        selectionColor: Theme.selection; selectedTextColor: Theme.ivory
                        leftPadding: 10; rightPadding: 10
                        validator: RegularExpressionValidator { regularExpression: /(?:[01]\d|2[0-3]):[0-5]\d/ }
                        background: Rectangle { color: Theme.voidColor; radius: 4; border.color: timeField.activeFocus ? Theme.vermilion : Theme.border }
                        onEditingFinished: {
                            if (acceptableInput && text !== NightLight.settings[modelData]) {
                                const changes = {}; changes[modelData] = text; NightLight.configure(changes);
                            }
                        }
                    }
                }
            }
        }
    }
    TextLabel { text: "Applies to all displays"; font.pixelSize: 11; color: Theme.muted }
    TextLabel { visible: NightLight.error !== ""; text: NightLight.error; font.pixelSize: 12; color: Theme.vermilion; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    Item { Layout.fillHeight: true }
}
