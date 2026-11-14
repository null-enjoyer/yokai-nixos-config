import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking

Item {
    id: root
    implicitWidth: 576
    implicitHeight: cards.implicitHeight
    readonly property var sample: Metrics.sample
    readonly property var physicalDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wired || device.type === DeviceType.Wifi)
    readonly property var networkDevice: physicalDevices.find(device => device.nmManaged && device.connected && device.type === DeviceType.Wired)
        ?? physicalDevices.find(device => device.nmManaged && device.connected && device.type === DeviceType.Wifi)
        ?? physicalDevices.find(device => device.nmManaged && device.type === DeviceType.Wired)
        ?? physicalDevices.find(device => device.nmManaged && device.type === DeviceType.Wifi)
        ?? physicalDevices.find(device => device.type === DeviceType.Wired) ?? physicalDevices[0] ?? null
    readonly property var connection: networkDevice?.networks.values.find(network => network.connected)
    readonly property string interfaceName: networkDevice?.name || (sample.network ?? [])[0]?.name || ""
    readonly property var volumes: sample.storage ?? []
    // Keep dropdown delegates alive when only usage counters change.
    readonly property string volumeChoicesSignature: JSON.stringify(volumes.map(item => ({ id: item.id, mount: item.mount, device: item.device })))
    readonly property var volumeChoices: JSON.parse(volumeChoicesSignature)
    property string volumeId: ""
    readonly property var volume: volumes.find(item => item.id === volumeId) ?? volumes[0]
    readonly property string periodLabel: ({900: "15m", 3600: "1h", 21600: "6h", 86400: "24h"})[NetworkHistory.period] ?? "15m"
    readonly property string historyNote: {
        if (interfaceName === "") return "No network interface available.";
        if (NetworkHistory.error !== "") return NetworkHistory.error + (NetworkHistory.hasCoverage ? " Showing cached history." : "");
        if (!NetworkHistory.hasCoverage) return NetworkHistory.loading ? "Loading history…" : "Collecting history…";
        const available = Math.max(0, NetworkHistory.windowEnd - Math.max(NetworkHistory.windowStart, NetworkHistory.observedSince));
        if (available < NetworkHistory.period - 5) {
            const duration = available < 60 ? Math.floor(available) + "s" : available < 3600 ? Math.floor(available / 60) + "m" : (available / 3600).toFixed(1) + "h";
            return "Collecting history · " + duration + " of " + periodLabel + " available";
        }
        return "Selected period · gaps show missing observations";
    }
    readonly property bool twoColumns: width >= 460

    function valid(value) { return typeof value === "number" && isFinite(value); }
    function percentage(value) { return valid(value) ? Math.round(value) + "%" : "—"; }
    function temperature(value) { return valid(value) ? Math.round(value) + "°C" : "—"; }
    function capacity(used, total) { return valid(used) && valid(total) ? used.toFixed(1) + " / " + total.toFixed(1) + " GiB" : "—"; }
    function bytes(value, rate) {
        if (!valid(value) || value < 0) return "—";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
        return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit] + (rate ? "/s" : "");
    }
    Binding { target: NetworkHistory; property: "interfaceName"; value: root.interfaceName }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ColumnLayout {
            id: cards
            width: scroll.availableWidth
            spacing: 12
            GridLayout {
                Layout.fillWidth: true
                columns: root.twoColumns ? 2 : 1
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    model: ["CPU", "GPU"]
                    SystemMetricCard {
                        required property string modelData
                        readonly property bool processor: modelData === "CPU"
                        readonly property var metricValue: processor ? root.sample.cpu : root.sample.gpu
                        readonly property var metricTemperature: processor ? root.sample.cpuTemp : root.sample.gpuTemp
                        Layout.fillWidth: true
                        Layout.preferredHeight: 160
                        title: modelData
                        detail: processor ? (root.sample.cpuName || "Processor") : (root.sample.gpuName || "Graphics processor")
                        iconName: processor ? "cpu-symbolic" : "video-display-symbolic"
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            ColumnLayout {
                                spacing: 5
                                TextLabel { text: "Temperature"; color: Theme.muted; font.pixelSize: 11 }
                                TextLabel { text: root.temperature(metricTemperature); font.family: "JetBrains Mono"; font.pixelSize: 17; color: root.valid(metricTemperature) && metricTemperature >= 85 ? Theme.vermilion : Theme.ivory }
                                TextLabel { visible: !processor; text: root.capacity(root.sample.gpuUsed, root.sample.gpuTotal) + " VRAM"; color: Theme.muted; font.pixelSize: 10 }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                spacing: 3
                                TextLabel { Layout.alignment: Qt.AlignRight; text: "Usage"; color: Theme.muted; font.pixelSize: 11 }
                                TextLabel { Layout.alignment: Qt.AlignRight; text: root.percentage(metricValue); font.family: "JetBrains Mono"; font.pixelSize: 28; color: root.valid(metricValue) && metricValue >= 85 ? Theme.vermilion : Theme.ivory }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 3
                            radius: 1.5
                            color: Theme.border
                            Rectangle {
                                width: parent.width * (root.valid(metricValue) ? Math.max(0, Math.min(100, metricValue)) / 100 : 0)
                                height: parent.height
                                radius: parent.radius
                                color: root.valid(metricValue) && metricValue >= 85 ? Theme.vermilion : Theme.ivory
                                Behavior on width { NumberAnimation { duration: 180 } }
                            }
                        }
                    }
                }
                SystemMetricCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 206
                    title: "Memory"
                    iconName: "media-flash-symbolic"
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14
                        MetricGauge { percent: root.sample.ram; Layout.alignment: Qt.AlignVCenter }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            TextLabel { text: "In use"; color: Theme.muted; font.pixelSize: 11 }
                            TextLabel { Layout.fillWidth: true; text: root.valid(root.sample.ramUsed) ? root.sample.ramUsed.toFixed(1) + " GiB" : "—"; font.family: "JetBrains Mono"; font.pixelSize: 20 }
                            TextLabel { Layout.fillWidth: true; text: root.valid(root.sample.ramTotal) ? "of " + root.sample.ramTotal.toFixed(1) + " GiB" : "Total unavailable"; color: Theme.muted; font.pixelSize: 11 }
                        }
                    }
                    TextLabel { Layout.fillWidth: true; text: "Physical memory"; color: Theme.muted; font.pixelSize: 11 }
                }
                SystemMetricCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 206
                    title: "Storage"
                    iconName: "drive-harddisk-symbolic"
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 14
                        MetricGauge { percent: root.volume?.percent; Layout.alignment: Qt.AlignVCenter }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            TextLabel { text: "In use"; color: Theme.muted; font.pixelSize: 11 }
                            TextLabel { Layout.fillWidth: true; text: root.valid(root.volume?.used) ? root.volume.used.toFixed(1) + " GiB" : "—"; font.family: "JetBrains Mono"; font.pixelSize: 19 }
                            TextLabel { Layout.fillWidth: true; text: root.valid(root.volume?.total) ? "of " + root.volume.total.toFixed(1) + " GiB" : "Total unavailable"; color: Theme.muted; font.pixelSize: 11 }
                        }
                    }
                    ComboBox {
                        id: storageChoice
                        Layout.fillWidth: true
                        implicitHeight: 30
                        model: root.volumeChoices
                        textRole: "mount"
                        currentIndex: Math.max(0, root.volumeChoices.findIndex(item => item.id === root.volume?.id))
                        enabled: root.volumeChoices.length > 1
                        displayText: root.volume ? root.volume.mount + " · " + root.volume.device : "No storage data"
                        onActivated: index => root.volumeId = root.volumeChoices[index].id
                        contentItem: TextLabel { text: storageChoice.displayText; color: Theme.muted; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 8; rightPadding: 24 }
                        background: Rectangle { radius: 4; color: storageChoice.hovered ? Theme.elevated : "#50202024"; border.width: 1; border.color: Theme.border }
                        indicator: TextLabel { x: storageChoice.width - width - 9; anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: Theme.muted; font.pixelSize: 14 }
                        delegate: ItemDelegate {
                            id: storageOption
                            required property int index
                            required property var modelData
                            width: storageChoice.width
                            contentItem: TextLabel { text: modelData.mount + " · " + modelData.device; font.pixelSize: 12 }
                            background: Rectangle { color: storageOption.highlighted ? Theme.elevated : Theme.surface }
                        }
                        popup: Popup {
                            y: storageChoice.height + 4
                            width: storageChoice.width
                            padding: 4
                            implicitHeight: Math.min(200, contentItem.implicitHeight + 8)
                            background: Rectangle { radius: 5; color: Theme.surface; border.color: Theme.border; border.width: 1 }
                            contentItem: ListView { clip: true; implicitHeight: contentHeight; model: storageChoice.popup.visible ? storageChoice.delegateModel : null; currentIndex: storageChoice.highlightedIndex }
                        }
                    }
                }
            }
            SystemMetricCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 306
                title: "Network"
                detail: root.connection?.name || (root.networkDevice?.connected ? root.interfaceName : root.interfaceName ? root.interfaceName + " · Disconnected" : "No network interface")
                iconName: root.networkDevice?.type === DeviceType.Wifi ? "network-wireless-symbolic" : "network-wired-symbolic"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [{label: "15m", seconds: 900}, {label: "1h", seconds: 3600}, {label: "6h", seconds: 21600}, {label: "24h", seconds: 86400}]
                        YokaiButton {
                            required property var modelData
                            text: modelData.label
                            implicitHeight: 28
                            Layout.fillWidth: true
                            highlighted: NetworkHistory.period === modelData.seconds
                            Accessible.name: modelData.label + " network history"
                            onClicked: NetworkHistory.period = modelData.seconds
                        }
                    }
                }
                NetworkGraph {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    samples: NetworkHistory.points
                    windowStart: NetworkHistory.windowStart
                    windowEnd: NetworkHistory.windowEnd
                    placeholder: root.interfaceName === "" ? "No network interface" : NetworkHistory.loading ? "Loading history…" : "Collecting history…"
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Repeater {
                        model: ["Download", "Upload"]
                        ColumnLayout {
                            required property string modelData
                            readonly property bool download: modelData === "Download"
                            Layout.fillWidth: true
                            spacing: 4
                            TextLabel { text: (download ? "↓ " : "↑ ") + modelData; color: download ? Theme.ivory : Theme.vermilion; font.pixelSize: 11 }
                            TextLabel { Layout.fillWidth: true; text: root.bytes(download ? NetworkHistory.latest?.download : NetworkHistory.latest?.upload, true); font.family: "JetBrains Mono"; font.pixelSize: 17 }
                            TextLabel { Layout.fillWidth: true; text: root.bytes(download ? NetworkHistory.totals?.download : NetworkHistory.totals?.upload, false) + " in " + root.periodLabel; color: Theme.muted; font.family: "JetBrains Mono"; font.pixelSize: 10 }
                        }
                    }
                }
                TextLabel { Layout.fillWidth: true; text: root.historyNote; color: Theme.muted; font.pixelSize: 10 }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.twoColumns ? 2 : 1
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    model: ["sink", "source"]
                    Rectangle {
                        required property string modelData
                        readonly property var audioDevice: modelData === "sink" ? Audio.sink : Audio.source
                        Layout.fillWidth: true
                        implicitHeight: audio.implicitHeight + 28
                        radius: 8
                        color: "#65202024"
                        border.width: 1
                        border.color: "#7034343A"
                        AudioControl {
                            id: audio
                            anchors.fill: parent
                            anchors.margins: 14
                            kind: modelData
                            label: modelData === "sink" ? "Output" : "Microphone"
                            device: audioDevice
                            detail: audioDevice?.description ?? "No device available"
                        }
                    }
                }
            }
        }
    }
}
