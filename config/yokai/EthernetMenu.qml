import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

PanelMenu {
    id: root
    required property var device
    readonly property var network: device?.network ?? null
    readonly property bool changing: device?.state === ConnectionState.Connecting
        || device?.state === ConnectionState.Disconnecting || (network?.stateChanging ?? false)
    property string message: ""
    heading: "Ethernet"
    fitContents: true

    function toggleConnection() {
        if (!device || changing) return;
        message = "";
        if (device.connected) device.disconnect();
        else if (device.hasLink && network?.known) network.connect();
    }
    function speedLabel(speed) {
        if (!device?.hasLink || !speed) return "—";
        return speed >= 1000 ? speed / 1000 + " Gbit/s" : speed + " Mbit/s";
    }
    onVisibleChanged: if (!visible) message = ""
    onDeviceChanged: message = ""

    RowLayout {
        Layout.fillWidth: true
        TextLabel {
            Layout.fillWidth: true
            text: !root.device ? "No Ethernet adapter" : !root.device.hasLink
                ? "Cable unplugged" : ConnectionState.toString(root.device.state)
            color: Theme.muted
            font.pixelSize: 13
        }
        YokaiButton {
            text: root.changing ? "Please wait…" : root.device?.connected ? "Disconnect" : "Connect"
            enabled: root.device !== null && !root.changing
                && (root.device.connected || root.device.hasLink && (root.network?.known ?? false))
            onClicked: root.toggleConnection()
        }
    }
    GridLayout {
        visible: root.device !== null
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 16
        rowSpacing: 12
        TextLabel { text: "Interface"; color: Theme.muted; font.pixelSize: 12 }
        TextLabel { Layout.fillWidth: true; text: root.device?.name ?? "—"; font.family: "JetBrains Mono"; font.pixelSize: 12; horizontalAlignment: Text.AlignRight }
        TextLabel { text: "Link speed"; color: Theme.muted; font.pixelSize: 12 }
        TextLabel { Layout.fillWidth: true; text: root.speedLabel(root.device?.linkSpeed); font.family: "JetBrains Mono"; font.pixelSize: 12; horizontalAlignment: Text.AlignRight }
        TextLabel { text: "MAC address"; color: Theme.muted; font.pixelSize: 12 }
        TextLabel { Layout.fillWidth: true; text: root.device?.address || "—"; font.family: "JetBrains Mono"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
    }
    TextLabel { Layout.fillWidth: true; visible: root.message !== ""; text: root.message; color: Theme.vermilion; font.pixelSize: 12; wrapMode: Text.WordWrap }
    YokaiButton {
        Layout.fillWidth: true
        text: "Network settings"
        onClicked: {
            root.closeReveal();
            Quickshell.execDetached(["nm-connection-editor"]);
        }
    }
    Connections {
        target: root.network
        function onConnectionFailed(reason) {
            root.message = "Connection failed · " + ConnectionFailReason.toString(reason);
        }
    }
}
