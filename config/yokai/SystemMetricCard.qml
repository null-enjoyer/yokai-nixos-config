import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root
    property string title: ""
    property string detail: ""
    property string iconName: "utilities-system-monitor-symbolic"
    property int padding: 16
    default property alias content: body.data
    implicitWidth: 280
    implicitHeight: contentColumn.implicitHeight + padding * 2
    radius: 8
    color: "#65202024"
    border.width: 1
    border.color: "#7034343A"

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            IconImage {
                implicitSize: 18
                source: Quickshell.iconPath(root.iconName, "utilities-system-monitor-symbolic")
                layer.enabled: true
                layer.effect: MultiEffect { brightness: 1; colorization: 1; colorizationColor: Theme.ivory }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                TextLabel { Layout.fillWidth: true; text: root.title; font.pixelSize: 15; font.weight: Font.Medium }
                TextLabel { Layout.fillWidth: true; visible: root.detail !== ""; text: root.detail; font.pixelSize: 11; color: Theme.muted }
            }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
        }
    }
}
