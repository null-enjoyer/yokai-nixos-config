import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

AttachedPopup {
    id: root
    objectName: "yokai-hub"
    heading: "YŌKAI"
    readonly property real maximumHeight: Math.max(1, Math.min(740, (screen?.height ?? 800) - 64))
    readonly property real naturalHeight: header.implicitHeight + body.implicitHeight + 66
    implicitWidth: 430
    implicitHeight: maximumHeight
    targetHeight: Math.min(maximumHeight, naturalHeight)
    resizeFromBottom: false

    function runSessionAction(action) {
        const commands = {
            lock: ["yokai-shell", "lock"],
            sleep: ["yokai-shell", "suspend"],
            logout: ["hyprctl", "dispatch", "hl.dsp.exit()"],
            restart: ["systemctl", "reboot"],
            poweroff: ["systemctl", "poweroff"]
        };
        if (!commands[action]) return;
        closeReveal();
        Quickshell.execDetached(commands[action]);
    }
    onVisibleChanged: if (!visible) session.clearConfirmation()

    popupContents: [
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24; anchors.leftMargin: 38
            spacing: 18
            RowLayout {
                id: header
                Layout.fillWidth: true
                TextLabel { text: "YŌKAI"; font.pixelSize: 18; font.letterSpacing: 1.4; Layout.fillWidth: true }
                CloseButton { onClicked: root.closeReveal() }
            }
            Flickable {
                id: viewport
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                contentWidth: width; contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ColumnLayout {
                    id: body
                    width: viewport.width
                    spacing: 18
                    MediaCard { Layout.fillWidth: true; monitoring: root.visible && !root.closing }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: Infinity
                        spacing: 12
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12
                            TextLabel { text: Weather.city; font.pixelSize: 13; color: Theme.muted; Layout.maximumWidth: 220 }
                        }
                        RowLayout {
                            visible: Weather.ready
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 14
                            IconImage { implicitSize: 34; source: Quickshell.iconPath(Weather.iconName) }
                            TextLabel { text: Math.round(Weather.temperature) + "°"; font.pixelSize: 42; font.weight: Font.Light }
                            ColumnLayout {
                                spacing: 5
                                TextLabel { text: Weather.condition; font.pixelSize: 14; Layout.maximumWidth: 190 }
                                TextLabel { text: "Feels like " + Math.round(Weather.feelsLike) + "°"; color: Theme.muted; font.pixelSize: 13 }
                                TextLabel { text: "High " + Math.round(Weather.high) + "°  ·  Low " + Math.round(Weather.low) + "°"; color: Theme.muted; font.pixelSize: 13 }
                            }
                        }
                        RowLayout {
                            visible: Weather.ready && Weather.forecast.length > 0
                            Layout.fillWidth: true
                            Layout.maximumWidth: Infinity
                            spacing: 14
                            Repeater {
                                model: Weather.forecast.slice(0, 3)
                                ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1; Layout.maximumWidth: Infinity; spacing: 6
                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 8
                                        TextLabel { text: modelData.day; font.pixelSize: 13; color: Theme.muted }
                                        IconImage { implicitSize: 18; source: Quickshell.iconPath(modelData.iconName) }
                                    }
                                    TextLabel { Layout.alignment: Qt.AlignHCenter; text: Math.round(modelData.high) + "° / " + Math.round(modelData.low) + "°"; font.family: "JetBrains Mono"; font.pixelSize: 13; color: Theme.muted }
                                }
                            }
                        }
                        TextLabel {
                            Layout.fillWidth: true
                            visible: !Weather.ready || Weather.stale || Weather.error !== ""
                            text: !Weather.ready ? (Weather.busy ? "Loading weather…" : Weather.error || "Weather is unavailable.") : "Cached weather · " + (Weather.error ? "Update unavailable" : "Waiting for update")
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.muted; font.pixelSize: 13; wrapMode: Text.Wrap
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
                    SessionControls { id: session; Layout.fillWidth: true; onActionRequested: action => root.runSessionAction(action) }
                }
            }
        }
    ]
    contentItem.focus: true
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeReveal(); event.accepted = true; }
    }
}
