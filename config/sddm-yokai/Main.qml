import QtQuick
import "wallpaper" as Background
import QtQml.Models

Rectangle {
    id: root
    width: 1280
    height: 850
    color: "#09090B"

    property date now: new Date()
    property string loginUser: ""
    property bool authenticating: false
    property string feedback: ""
    readonly property int sessionIndex: sessionModel.count > 0
        ? Math.max(0, Math.min(sessionModel.lastIndex, sessionModel.count - 1)) : -1
    readonly property bool ready: loginUser.length > 0 && sessionIndex >= 0
    readonly property bool compact: height < 800

    // SDDM validates its remembered account when choosing lastIndex. Resolve
    // the account from that model row rather than trusting a stale lastUser.
    Instantiator {
        model: userModel
        delegate: QtObject { required property string name }
        onObjectAdded: (index, object) => {
            if (index === Math.max(0, userModel.lastIndex))
                root.loginUser = object.name;
        }
    }

    function submit() {
        if (!ready || authenticating || password.text.length === 0) return;
        authenticating = true;
        feedback = "";
        // SDDM owns PAM authentication and starting the selected desktop session.
        sddm.login(loginUser, password.text, sessionIndex);
        password.text = "";
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.authenticating = false;
            password.text = "";
            root.feedback = "Incorrect password. Try again.";
            password.forceActiveFocus();
        }
        function onLoginSucceeded() {
            password.text = "";
            root.feedback = "";
        }
        function onInformationMessage(message) { root.feedback = message; }
    }

    Background.Wallpaper {
        anchors.fill: parent
        directory: Qt.resolvedUrl("wallpapers")
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
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "HH:mm")
            color: "#F0EDE6"
            font { family: "Inter"; pixelSize: root.compact ? 76 : 110; weight: Font.Light; letterSpacing: -5 }
            textFormat: Text.PlainText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, d MMMM")
            color: "#F0EDE6"
            opacity: 0.8
            font { family: "Inter"; pixelSize: 15 }
            textFormat: Text.PlainText
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(280, root.width - 48)
        height: 48
        radius: 5
        color: "#09090B"
        border.color: root.feedback || password.activeFocus ? "#D92B3A" : "#34343A"
        border.width: 1

        TextInput {
            id: password
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            onTextEdited: root.feedback = ""
            onAccepted: root.submit()
            enabled: root.ready && !root.authenticating
            focus: true
            color: "#F0EDE6"
            selectionColor: "#681723"
            selectedTextColor: "#F0EDE6"
            font { family: "Inter"; pixelSize: 17 }
            echoMode: TextInput.Password
            passwordCharacter: "•"
            passwordMaskDelay: 0
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            maximumLength: 1024
            clip: true
            Keys.onEscapePressed: text = ""
            onEnabledChanged: if (enabled) forceActiveFocus()
        }
        Text {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
            text: root.feedback || (!root.ready ? "Login unavailable" : root.authenticating ? "Verifying…" : "Enter password")
            color: root.feedback ? "#D92B3A" : "#929098"
            font { family: "Inter"; pixelSize: 13 }
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            visible: password.text.length === 0
        }
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }
}
