import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

PanelMenu {
    id: root
    required property bool microphone
    property bool choosingDevice: false
    readonly property var device: microphone ? Audio.source : Audio.sink
    readonly property var devices: microphone ? Audio.state.inputs : Audio.state.outputs
    readonly property var streams: microphone ? Audio.recording : Audio.playback
    fitContents: true
    heading: microphone ? "Microphone" : "Volume"
    onVisibleChanged: if (!visible) choosingDevice = false
    ScrollView {
        id: scroll
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth
        contentHeight: audioContents.implicitHeight
        implicitHeight: contentHeight + topPadding + bottomPadding
        clip: true
        ColumnLayout {
            id: audioContents
            width: scroll.availableWidth
            spacing: 18
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                TextLabel { text: "Device"; font.pixelSize: 11; color: Theme.muted }
                YokaiButton {
                    Layout.fillWidth: true
                    text: (root.device?.description ?? "No device") + (root.choosingDevice ? "  ▴" : "  ▾")
                    onClicked: root.choosingDevice = !root.choosingDevice
                }
                Repeater {
                    model: root.choosingDevice ? root.devices : []
                    YokaiButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.description
                        highlighted: modelData.name === root.device?.name
                        onClicked: { Audio.selectDevice(root.microphone ? "input" : "output", modelData); root.choosingDevice = false; }
                    }
                }
            }
            AudioControl { Layout.fillWidth: true; kind: root.microphone ? "source" : "sink"; device: root.device; label: "Master volume" }
            TextLabel { text: "Applications"; font.pixelSize: 14; Layout.topMargin: 14 }
            TextLabel { visible: root.streams.count === 0; text: root.microphone ? "No applications recording" : "No applications playing audio"; color: Theme.muted; font.pixelSize: 12 }
            Repeater {
                model: root.streams
                AudioControl {
                    required property var model
                    Layout.fillWidth: true
                    kind: root.microphone ? "source-output" : "sink-input"
                    device: ({id: model.streamId, description: model.description, volume: model.volume, muted: model.muted})
                    detail: model.detail !== model.description ? model.detail : ""
                }
            }
            TextLabel { visible: Audio.error !== ""; text: Audio.error; color: Theme.vermilion; font.pixelSize: 12 }
        }
    }
}
