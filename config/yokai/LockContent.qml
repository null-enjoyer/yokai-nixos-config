import QtQuick
import Quickshell

Item {
    id: root
    required property var controller
    property date now: new Date()
    readonly property bool compact: height < 800

    Wallpaper {
        anchors.fill: parent
        directory: "file://" + (Quickshell.env("YOKAI_WALLPAPERS") || Quickshell.shellPath("../../wallpapers"))
    }
    Rectangle { anchors.fill: parent; color: "#8509090B" }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#6009090B" }
            GradientStop { position: 0.45; color: "#0009090B" }
            GradientStop { position: 1; color: "#EE09090B" }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * (root.compact ? 0.12 : 0.17)
        spacing: 12
        TextLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            font.pixelSize: root.compact ? 76 : 110
            font.weight: Font.Light
            font.letterSpacing: -5
        }
        TextLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, d MMMM")
            font.pixelSize: 15
            color: Theme.ivory
            opacity: 0.8
        }
    }

    Rectangle {
        id: inputFrame
        anchors.centerIn: parent
        width: Math.min(280, root.width - 48)
        height: 48
        radius: 5
        color: Theme.voidColor
        border.color: root.controller.feedback || password.activeFocus ? Theme.vermilion : Theme.border
        border.width: 1

        TextInput {
            id: password
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            text: root.controller.input
            onTextEdited: root.controller.edited(text)
            onAccepted: root.controller.submit()
            enabled: root.controller.canSubmit
            focus: true
            color: Theme.ivory
            selectionColor: Theme.selection
            selectedTextColor: Theme.ivory
            font.family: "Inter"
            font.pixelSize: 17
            echoMode: root.controller.responseVisible ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            passwordMaskDelay: 0
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            maximumLength: 1024
            clip: true
            Keys.onEscapePressed: root.controller.input = ""
            onEnabledChanged: if (enabled) forceActiveFocus()
        }
        TextLabel {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            text: root.controller.feedback || (root.controller.waiting ? "Verifying…" : "Enter password")
            color: root.controller.feedback ? Theme.vermilion : Theme.muted
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            visible: password.text.length === 0
        }
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
}
