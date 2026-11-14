import QtQuick
import QtQuick.Layouts
import Quickshell

AttachedPopup {
    id: root
    default property alias contents: body.data
    property bool fitContents: false
    readonly property real maximumHeight: Math.min(640, (screen?.height ?? 800) - 64)
    readonly property real naturalHeight: menuLayout.implicitHeight + 48
    targetHeight: fitContents ? Math.min(maximumHeight, naturalHeight) : implicitHeight
    resizeFromBottom: fitContents
    implicitWidth: 394
    implicitHeight: maximumHeight
    popupContents: [
        ColumnLayout {
            id: menuLayout
            anchors.fill: parent; anchors.margins: 24; spacing: 18
            anchors.leftMargin: 38
            RowLayout {
                TextLabel { text: root.heading; font.pixelSize: 18; Layout.fillWidth: true }
                CloseButton { onClicked: root.closeReveal() }
            }
            ColumnLayout { id: body; Layout.fillWidth: true; Layout.fillHeight: true; spacing: 18 }
        }
    ]
    contentItem.focus: true
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeReveal(); event.accepted = true; }
    }
}
