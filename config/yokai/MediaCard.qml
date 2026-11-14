import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    objectName: "media-card"
    property bool monitoring: false
    readonly property var player: Media.player
    readonly property bool hasTrack: !!player && (!!player.trackTitle || !!player.trackArtist || !!player.trackAlbum || player.lengthSupported && player.length > 0 || player.isPlaying)
    readonly property bool hasTimeline: !!player && player.positionSupported && player.lengthSupported && player.length > 0
    spacing: 14

    RowLayout {
        TextLabel { text: "NOW PLAYING"; font.family: "JetBrains Mono"; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.muted; Layout.fillWidth: true }
        YokaiButton {
            objectName: "media-player-selector"
            text: root.player ? (root.player.identity || "Media player") + (Media.players.length > 1 ? "  " + (Media.playerIndex + 1) + "/" + Media.players.length + "  ›" : "") : ""
            visible: !!root.player
            enabled: Media.players.length > 1
            Layout.maximumWidth: 200
            implicitHeight: 28
            onClicked: Media.selectNextPlayer()
        }
    }

    RowLayout {
        spacing: 16
        Rectangle {
            Layout.preferredWidth: 80; Layout.preferredHeight: 80
            color: Theme.elevated; radius: 4; clip: true
            Image {
                id: artwork
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            TextLabel { anchors.centerIn: parent; text: "♪"; font.pixelSize: 32; color: Theme.muted; visible: !artwork.visible }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 7
            TextLabel {
                Layout.fillWidth: true
                text: root.hasTrack ? root.player.trackTitle || "Untitled track" : "Nothing playing"
                font.pixelSize: 16
                maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight
            }
            TextLabel {
                Layout.fillWidth: true
                text: root.hasTrack ? root.player.trackArtist || root.player.identity || "Unknown artist" : "Start music in a media app."
                color: Theme.muted; font.pixelSize: 12
            }
            TextLabel {
                Layout.fillWidth: true
                visible: !!root.player?.trackAlbum
                text: root.player?.trackAlbum ?? ""
                color: Theme.muted; font.pixelSize: 11
            }
        }
    }

    ColumnLayout {
        visible: root.hasTimeline
        Layout.fillWidth: true
        spacing: 0
        YokaiSlider {
            id: timeline
            Layout.fillWidth: true
            implicitHeight: 24
            from: 0; to: root.hasTimeline ? root.player.length : 1
            enabled: root.hasTimeline && root.player.canSeek
            onMoved: if (root.hasTimeline && root.player.canSeek) root.player.position = value
            Binding {
                target: timeline; property: "value"
                value: root.hasTimeline ? Math.max(0, Math.min(timeline.to, root.player.position)) : 0
                when: !timeline.pressed
                restoreMode: Binding.RestoreBindingOrValue
            }
        }
        RowLayout {
            Layout.fillWidth: true
            TextLabel { text: Media.formatTime(timeline.value); font.family: "JetBrains Mono"; font.pixelSize: 10; color: Theme.muted }
            Item { Layout.fillWidth: true }
            TextLabel { text: Media.formatTime(root.player?.length ?? 0); font.family: "JetBrains Mono"; font.pixelSize: 10; color: Theme.muted }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 12
        IconButton {
            implicitWidth: 40; implicitHeight: 40
            iconSize: 20
            iconName: "media-skip-backward-symbolic"; tooltip: "Previous track"
            enabled: !!root.player?.canGoPrevious
            iconColor: enabled ? Theme.ivory : Theme.muted
            onClicked: root.player.previous()
        }
        IconButton {
            objectName: "media-play-pause"
            implicitWidth: 52; implicitHeight: 42
            iconSize: 24
            iconName: root.player?.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
            tooltip: root.player?.isPlaying ? "Pause" : "Play"
            enabled: !!root.player && (root.player.isPlaying ? root.player.canPause : root.player.canPlay)
            iconColor: enabled ? Theme.ivory : Theme.muted
            selected: enabled
            onClicked: Media.togglePlayback()
        }
        IconButton {
            implicitWidth: 40; implicitHeight: 40
            iconSize: 20
            iconName: "media-skip-forward-symbolic"; tooltip: "Next track"
            enabled: !!root.player?.canGoNext
            iconColor: enabled ? Theme.ivory : Theme.muted
            onClicked: root.player.next()
        }
    }

    Timer {
        interval: 1000; repeat: true
        running: root.monitoring && root.hasTimeline && !!root.player?.isPlaying
        onTriggered: root.player.positionChanged()
    }
}
