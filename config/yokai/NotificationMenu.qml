import QtQuick

AttachedPopup {
    id: root
    heading: "Notification center"
    readonly property bool hovered: hover.hovered
    dismissOnOutsideClick: false
    implicitWidth: 460
    implicitHeight: Math.min(620, (screen?.height ?? 800) - 64)
    targetHeight: Math.min(implicitHeight, Math.max(260, pane.naturalHeight + 48))
    onVisibleChanged: if (visible) NotificationCenter.markRead()
    HoverHandler { id: hover; parent: root.contentItem }
    NotificationPane {
        id: pane
        anchors.fill: parent
        anchors { leftMargin: 38; rightMargin: 24; topMargin: 24; bottomMargin: 24 }
        onCloseRequested: root.closeReveal()
    }
    contentItem.focus: true
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeReveal(); event.accepted = true; }
    }
}
