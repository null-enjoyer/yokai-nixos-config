import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string kind
    property var device: null
    property string label: device?.description ?? "Unavailable"
    property string detail: ""
    readonly property bool microphone: kind === "source" || kind === "source-output"
    spacing: 8
    RowLayout {
        Layout.fillWidth: true
        TextLabel { text: root.label; font.pixelSize: 14; Layout.fillWidth: true }
        TextLabel { text: (root.device?.volume ?? 0) + "%"; color: Theme.muted; font.pixelSize: 12; font.family: "JetBrains Mono" }
        IconButton {
            implicitWidth: 30; implicitHeight: 30
            iconColor: Theme.ivory
            iconName: root.microphone ? (root.device?.muted ? "microphone-disabled-symbolic" : "audio-input-microphone-symbolic") : (root.device?.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic")
            tooltip: root.device?.muted ? "Unmute" : "Mute"
            enabled: root.device !== null
            onClicked: Audio.toggleMute(root.kind, root.device)
        }
    }
    YokaiSlider {
        Layout.fillWidth: true
        from: 0; to: 100; stepSize: 1
        value: root.device?.volume ?? 0
        enabled: root.device !== null
        onMoved: Audio.setVolume(root.kind, root.device, value)
    }
    TextLabel { Layout.fillWidth: true; visible: root.detail !== ""; text: root.detail; font.pixelSize: 11; color: Theme.muted }
}
