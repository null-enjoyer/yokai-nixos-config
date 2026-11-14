import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    required property bool microphone
    signal settingsRequested()
    readonly property var device: microphone ? Audio.source : Audio.sink
    readonly property string kind: microphone ? "source" : "sink"
    readonly property bool recording: microphone && (Audio.microphoneRecording ?? false)
    implicitHeight: 52
    color: mouse.containsMouse ? Theme.elevated : "transparent"
    radius: 4
    ColumnLayout {
        anchors.centerIn: parent; spacing: 5
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Theme.railIconSize; implicitHeight: Theme.railIconSize
            IconImage {
                anchors.fill: parent
                source: Quickshell.iconPath(root.microphone ? (root.device?.muted ? "microphone-disabled-symbolic" : "audio-input-microphone-symbolic") : (root.device?.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"))
                layer.enabled: true
                layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: Theme.ivory }
            }
            Rectangle {
                visible: root.recording
                anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -2 }
                width: 5; height: 5; radius: 3
                color: Theme.vermilion
            }
        }
        TextLabel { Layout.alignment: Qt.AlignHCenter; text: (root.device?.volume ?? 0) + "%"; font.family: "JetBrains Mono"; font.pixelSize: 12; color: Theme.white }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.LeftButton) Audio.toggleMute(root.kind, root.device);
            else root.settingsRequested();
        }
        onWheel: event => { Audio.setVolume(root.kind, root.device, (root.device?.volume ?? 0) + (event.angleDelta.y > 0 ? 5 : -5)); event.accepted = true; }
    }
}
