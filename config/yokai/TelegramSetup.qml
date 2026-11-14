pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    visible: TelegramSearch.setupVisible
    screen: TelegramSearch.setupScreen
    implicitWidth: 440
    implicitHeight: form.implicitHeight + 48
    anchors { right: true; top: true }
    margins { right: 64; top: 64 }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yokai-telegram-setup"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    readonly property string state: TelegramSearch.state
    property bool phoneFallback: false
    property string validationError: ""
    readonly property bool credentials: state === "credentials"
    readonly property bool phone: !credentials && (state === "phone" || state === "qr") && phoneFallback
    readonly property bool challenge: ["code", "password", "email", "emailCode"].includes(state)
    readonly property string inputLabel: phone ? "Phone number" : state === "code" ? "Login code" : state === "password" ? "Two-step verification password" : state === "email" ? "Email address" : "Email code"

    function clearFields() { apiId.text = ""; apiHash.text = ""; challengeInput.text = ""; validationError = ""; }
    function focusInput() {
        if (!visible) return;
        if (credentials) apiId.forceActiveFocus();
        else if (phone || challenge) challengeInput.forceActiveFocus();
        else content.forceActiveFocus();
    }
    function submit() {
        if (TelegramSearch.submitting) return;
        if (credentials) {
            const identifier = apiId.text.trim();
            if (!/^[1-9][0-9]*$/.test(identifier) || Number(identifier) >= 2147483648) {
                validationError = "API ID must be a positive number below 2147483648.";
                apiId.forceActiveFocus();
                return;
            }
            if (!/^[a-fA-F0-9]{32}$/.test(apiHash.text.trim())) {
                validationError = "API hash must contain exactly 32 hexadecimal characters (0–9, a–f).";
                apiHash.forceActiveFocus();
                return;
            }
            validationError = "";
            if (TelegramSearch.submit({type: "credentials", apiId: Number(apiId.text.trim()), apiHash: apiHash.text.trim()})) clearFields();
        } else if (phone || challenge) {
            if (!challengeInput.text.trim()) return;
            const type = phone ? "phone" : state;
            const request = {type: type};
            request[type] = state === "password" ? challengeInput.text : challengeInput.text.trim();
            if (TelegramSearch.submit(request)) challengeInput.text = "";
        }
    }
    onVisibleChanged: { clearFields(); if (visible) { phoneFallback = false; Qt.callLater(root.focusInput); } }
    onStateChanged: { clearFields(); Qt.callLater(root.focusInput); }
    onPhoneChanged: { challengeInput.text = ""; Qt.callLater(root.focusInput); }
    Connections { target: TelegramSearch; function onReadyChanged() { if (TelegramSearch.ready) root.clearFields(); } }

    Item {
        id: content
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { TelegramSearch.closeSetup(); event.accepted = true; }
        }
        FrostPanel {
            anchors.centerIn: parent
            width: root.width
            height: form.implicitHeight + padding * 2
            ColumnLayout {
                id: form
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 14
                TextLabel { text: "Connect Telegram"; font.pixelSize: 21; font.weight: Font.Medium }
                TextLabel {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    color: Theme.muted
                    font.pixelSize: 12
                    text: root.credentials ? "Enter your own Telegram API credentials once to connect chat search."
                        : TelegramSearch.ready ? "Telegram is connected. Your chats are available in Search."
                        : root.phone ? "Enter your phone number with the country code."
                        : root.state === "code" ? "Enter the login code sent by Telegram."
                        : root.state === "password" ? "Enter your Telegram two-step verification password." + (TelegramSearch.passwordHint ? " Hint: " + TelegramSearch.passwordHint : "")
                        : root.state === "email" ? "Telegram requires an email address to continue."
                        : root.state === "emailCode" ? "Enter the code sent to your email."
                        : root.state === "error" ? "Telegram could not connect. You can restart the integration to try again."
                        : "In Telegram, open Settings → Devices → Link Desktop Device, then scan this code."
                }
                AuthField {
                    id: apiId
                    visible: root.credentials
                    placeholderText: "API ID"
                    inputMethodHints: Qt.ImhDigitsOnly
                    onTextEdited: root.validationError = ""
                    onAccepted: apiHash.forceActiveFocus()
                }
                AuthField {
                    id: apiHash
                    visible: root.credentials
                    placeholderText: "API hash"
                    echoMode: TextInput.Password
                    onTextEdited: root.validationError = ""
                    onAccepted: root.submit()
                }
                YokaiButton {
                    Layout.fillWidth: true
                    visible: root.credentials
                    text: "Get API credentials at my.telegram.org ↗"
                    onClicked: {
                        TelegramSearch.closeSetup();
                        Qt.callLater(() => Quickshell.execDetached(["systemd-run", "--user", "--collect", "--property=Type=exec", "--", "brave", "https://my.telegram.org"]));
                    }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 224
                    Layout.preferredHeight: 224
                    visible: !root.credentials && !root.phone && (root.state === "phone" || root.state === "qr")
                    color: "white"
                    radius: 6
                    Image {
                        anchors.fill: parent
                        anchors.margins: 8
                        cache: false
                        source: TelegramSearch.qrPath ? "file://" + TelegramSearch.qrPath + "?revision=" + TelegramSearch.qrRevision : ""
                        fillMode: Image.PreserveAspectFit
                    }
                    TextLabel {
                        anchors.centerIn: parent
                        visible: !TelegramSearch.qrPath
                        text: TelegramSearch.submitting ? "Preparing QR code…" : "Generate a QR code to sign in"
                        color: Theme.surface
                        font.pixelSize: 12
                    }
                }
                AuthField {
                    id: challengeInput
                    visible: root.phone || root.challenge
                    placeholderText: root.inputLabel
                    echoMode: root.state === "password" ? TextInput.Password : TextInput.Normal
                    inputMethodHints: root.state === "password" ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNone
                    onAccepted: root.submit()
                }
                TextLabel {
                    Layout.fillWidth: true
                    visible: root.validationError !== "" || TelegramSearch.error !== ""
                    text: root.validationError || TelegramSearch.error
                    color: Theme.vermilion
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.pixelSize: 12
                }
                TextLabel {
                    visible: TelegramSearch.submitting
                    text: "Connecting…"
                    color: Theme.muted
                    font.pixelSize: 12
                }
                YokaiButton {
                    visible: !root.credentials && !TelegramSearch.ready
                    Layout.alignment: Qt.AlignLeft
                    implicitHeight: 28
                    text: "Change API credentials"
                    enabled: !TelegramSearch.submitting
                    onClicked: TelegramSearch.submit({type: "resetCredentials"})
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    YokaiButton {
                        visible: !TelegramSearch.ready && root.state !== "error"
                        text: root.credentials ? "Save and continue" : root.phone || root.challenge ? "Continue" : TelegramSearch.qrPath ? "Refresh QR code" : "Sign in with QR code"
                        highlighted: true
                        enabled: !TelegramSearch.submitting && (!(root.phone || root.challenge) || challengeInput.text.trim() !== "")
                        onClicked: {
                            if (root.credentials || root.phone || root.challenge) root.submit();
                            else TelegramSearch.submit({type: "qr"});
                        }
                    }
                    YokaiButton {
                        visible: !TelegramSearch.ready && (root.state === "phone" || root.state === "qr")
                        text: root.phone ? "Use QR code" : "Use phone number"
                        enabled: !TelegramSearch.submitting
                        onClicked: root.phoneFallback = !root.phoneFallback
                    }
                    YokaiButton {
                        visible: root.state === "error"
                        text: "Restart integration"
                        enabled: !TelegramSearch.submitting
                        onClicked: TelegramSearch.restartIntegration()
                    }
                    Item { Layout.fillWidth: true }
                    YokaiButton { text: TelegramSearch.ready ? "Done" : "Close"; onClicked: TelegramSearch.closeSetup() }
                }
            }
        }
        CloseButton {
            anchors { top: parent.top; right: parent.right; margins: 24 }
            tooltip: "Close"
            onClicked: TelegramSearch.closeSetup()
        }
    }
    component AuthField: TextField {
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        leftPadding: 12
        rightPadding: 12
        font.family: "Inter"
        font.pixelSize: 14
        color: Theme.ivory
        placeholderTextColor: Theme.muted
        selectionColor: Theme.selection
        selectedTextColor: Theme.ivory
        selectByMouse: true
        background: Rectangle {
            radius: 6
            color: "#20000000"
            border.color: parent.activeFocus ? Theme.vermilion : Theme.border
        }
    }
}
