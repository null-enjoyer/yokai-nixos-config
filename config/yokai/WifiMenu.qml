import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Networking

PanelMenu {
    id: root
    required property var device
    property var selectedNetwork: null
    property bool passwordNeeded: false
    property string message: ""
    readonly property var networks: device?.networks.values.slice().sort((a, b) => Number(b.connected) - Number(a.connected) || b.signalStrength - a.signalStrength) ?? []
    heading: "Wi-Fi"
    function usesPassword(network) {
        return [WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security);
    }
    function connectNetwork(network) {
        selectedNetwork = network;
        message = "";
        passwordNeeded = !network.known && usesPassword(network);
        password.clear();
        if (passwordNeeded) password.forceActiveFocus();
        else network.connect();
    }
    onVisibleChanged: {
        if (device) device.scannerEnabled = visible && Networking.wifiEnabled;
        if (!visible) { password.clear(); passwordNeeded = false; selectedNetwork = null; message = ""; }
    }
    RowLayout {
        Layout.fillWidth: true
        TextLabel { Layout.fillWidth: true; text: root.device ? (Networking.wifiEnabled ? "Enabled" : "Disabled") : "No Wi-Fi adapter"; color: Theme.muted; font.pixelSize: 13 }
        YokaiButton {
            text: Networking.wifiEnabled ? "Turn off" : "Turn on"
            enabled: root.device !== null && Networking.wifiHardwareEnabled
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }
    TextLabel { visible: !Networking.wifiHardwareEnabled; text: "Wi-Fi is blocked by a hardware switch"; font.pixelSize: 12; color: Theme.vermilion }
    ColumnLayout {
        visible: root.passwordNeeded
        Layout.fillWidth: true; spacing: 8
        TextLabel { Layout.fillWidth: true; text: root.selectedNetwork?.name ?? ""; font.pixelSize: 13 }
        TextField {
            id: password
            Layout.fillWidth: true; implicitHeight: 40
            leftPadding: 12; rightPadding: 12
            color: Theme.ivory; placeholderTextColor: Theme.muted
            selectionColor: Theme.selection; selectedTextColor: Theme.ivory
            font.family: "Inter"; font.pixelSize: 13
            placeholderText: "Network password"
            echoMode: TextInput.Password
            background: Rectangle { color: Theme.voidColor; radius: 4; border.color: password.activeFocus ? Theme.vermilion : Theme.border }
            onAccepted: if (connectButton.enabled) connectButton.clicked()
        }
        RowLayout {
            YokaiButton {
                id: connectButton
                text: "Connect"; enabled: password.text.length > 0 && !root.selectedNetwork?.stateChanging
                onClicked: { root.message = ""; root.selectedNetwork.connectWithPsk(password.text); password.clear(); }
            }
            YokaiButton { text: "Cancel"; onClicked: { root.passwordNeeded = false; password.clear(); } }
        }
    }
    TextLabel { Layout.fillWidth: true; visible: root.message !== ""; text: root.message; color: Theme.vermilion; font.pixelSize: 12; wrapMode: Text.WordWrap }
    ScrollView {
        id: scroll
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: scroll.availableWidth; spacing: 10
            Repeater {
                model: Networking.wifiEnabled ? root.networks : []
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 2
                    YokaiButton {
                        Layout.fillWidth: true
                        text: modelData.name + (modelData.connected ? "  · Connected" : "")
                        highlighted: modelData.connected
                        enabled: !modelData.stateChanging
                        onClicked: if (!modelData.connected) root.connectNetwork(modelData)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        TextLabel { Layout.fillWidth: true; text: modelData.stateChanging ? ConnectionState.toString(modelData.state) : Math.round(modelData.signalStrength * 100) + "% · " + WifiSecurityType.toString(modelData.security); font.pixelSize: 10; color: Theme.muted }
                        YokaiButton { visible: modelData.connected; text: "Disconnect"; implicitHeight: 28; onClicked: modelData.disconnect() }
                    }
                }
            }
            TextLabel { visible: Networking.wifiEnabled && root.networks.length === 0; text: root.device ? "Searching for networks…" : "No Wi-Fi adapter"; font.pixelSize: 12; color: Theme.muted }
        }
    }
    Connections {
        target: Networking
        function onWifiEnabledChanged() { if (root.visible && root.device) root.device.scannerEnabled = Networking.wifiEnabled; }
    }
    Connections {
        target: root.selectedNetwork
        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets && root.usesPassword(root.selectedNetwork)) {
                root.passwordNeeded = true;
                root.message = "Enter the network password";
                password.forceActiveFocus();
            } else root.message = "Connection failed · " + ConnectionFailReason.toString(reason);
        }
        function onConnectedChanged() {
            if (root.selectedNetwork?.connected) { root.passwordNeeded = false; password.clear(); root.message = ""; }
        }
    }
}
