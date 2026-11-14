import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Bluetooth

PanelMenu {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter?.devices.values.slice().sort((a, b) => Number(b.connected) - Number(a.connected) || Number(b.paired) - Number(a.paired) || a.name.localeCompare(b.name)) ?? []
    property var pairingDevice: null
    heading: "Bluetooth"
    onVisibleChanged: if (!visible && adapter) adapter.discovering = false
    RowLayout {
        Layout.fillWidth: true
        TextLabel { Layout.fillWidth: true; text: root.adapter ? BluetoothAdapterState.toString(root.adapter.state) : "No Bluetooth adapter"; font.pixelSize: 13; color: Theme.muted }
        YokaiButton { text: root.adapter?.enabled ? "Turn off" : "Turn on"; enabled: root.adapter !== null; onClicked: root.adapter.enabled = !root.adapter.enabled }
    }
    RowLayout {
        Layout.fillWidth: true
        TextLabel { Layout.fillWidth: true; text: root.adapter?.name ?? ""; font.pixelSize: 12; color: Theme.muted }
        YokaiButton {
            text: root.adapter?.discovering ? "Stop scan" : "Scan"
            enabled: root.adapter?.enabled ?? false
            onClicked: root.adapter.discovering = !root.adapter.discovering
        }
    }
    ScrollView {
        id: scroll
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: scroll.availableWidth; spacing: 20
            Repeater {
                model: root.devices
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 6
                    TextLabel { Layout.fillWidth: true; text: modelData.name || modelData.address; font.pixelSize: 14 }
                    TextLabel {
                        Layout.fillWidth: true
                        text: (modelData.pairing ? "Pairing…" : BluetoothDeviceState.toString(modelData.state)) + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "% battery" : "")
                        font.pixelSize: 11; color: Theme.muted
                    }
                    RowLayout {
                        YokaiButton {
                            text: modelData.pairing ? "Cancel" : modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"
                            enabled: (root.adapter?.enabled ?? false) && modelData.state !== BluetoothDeviceState.Connecting && modelData.state !== BluetoothDeviceState.Disconnecting
                            highlighted: modelData.connected
                            onClicked: {
                                if (modelData.pairing) modelData.cancelPair();
                                else if (modelData.connected) modelData.disconnect();
                                else if (modelData.paired) modelData.connect();
                                else { root.pairingDevice = modelData; modelData.pair(); }
                            }
                        }
                        YokaiButton { visible: modelData.paired; text: modelData.trusted ? "Trusted" : "Trust"; highlighted: modelData.trusted; onClicked: modelData.trusted = !modelData.trusted }
                    }
                }
            }
            TextLabel { visible: root.devices.length === 0; text: root.adapter?.discovering ? "Searching for devices…" : "Scan to discover devices"; font.pixelSize: 12; color: Theme.muted }
        }
    }
    Connections {
        target: root.pairingDevice
        function onPairedChanged() {
            if (root.pairingDevice?.paired) {
                root.pairingDevice.trusted = true;
                root.pairingDevice.connect();
                root.pairingDevice = null;
            }
        }
    }
}
