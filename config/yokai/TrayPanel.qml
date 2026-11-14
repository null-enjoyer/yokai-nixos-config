import QtQuick
import Quickshell
import Quickshell.Widgets

AttachedPopup {
    id: root
    readonly property bool hovered: hover.hovered
    readonly property bool expanded: appMenu.trayItem !== null
    readonly property real contextWidth: Math.min(implicitWidth - 92, appMenu.naturalWidth)
    readonly property real contextHeight: Math.min(appMenu.naturalHeight, Math.max(0, implicitHeight - 24))
    readonly property real contextTop: Math.max(0, revealedHeight - contextHeight - 24)
    heading: "Tray"
    dismissOnOutsideClick: false
    resizeFromBottom: true
    targetWidth: expanded ? 92 + contextWidth : 74
    targetHeight: Math.min(620, Math.max(Math.max(30, Tray.items.length * 34 - 4) + 24, expanded ? appMenu.naturalHeight + 24 : 0), (screen?.height ?? 800) - 64)
    surfaceColumnWidth: expanded ? 74 : 0
    surfaceSideTop: expanded && contextTop > 12 ? contextTop : 0
    surfaceSideHeight: expanded ? revealedHeight - surfaceSideTop : 0
    implicitWidth: 428
    implicitHeight: Math.min(620, (screen?.height ?? 800) - 64)
    onVisibleChanged: if (!visible) appMenu.trayItem = null
    HoverHandler { id: hover; parent: root.contentItem }
    Column {
        id: icons
        anchors { left: parent.left; leftMargin: 28; bottom: parent.bottom; bottomMargin: 10 }
        width: 32
        spacing: 4
        Repeater {
            model: Tray.items
            Rectangle {
                id: trayButton
                required property var modelData
                width: 32; height: 30
                radius: 4
                color: mouse.containsMouse || appMenu.trayItem === modelData ? Theme.elevated : "transparent"
                IconImage { anchors.centerIn: parent; implicitSize: 22; source: trayButton.modelData.icon }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton || trayButton.modelData.onlyMenu) {
                            if (trayButton.modelData.hasMenu) appMenu.trayItem = appMenu.trayItem === trayButton.modelData ? null : trayButton.modelData;
                        } else if (event.button === Qt.MiddleButton) trayButton.modelData.secondaryActivate();
                        else { trayButton.modelData.activate(); root.closeReveal(); }
                    }
                    onWheel: event => trayButton.modelData.scroll(event.angleDelta.y, false)
                }
            }
        }
        TextLabel { visible: Tray.items.length === 0; text: "Empty"; color: Theme.muted; font.pixelSize: 12 }
    }
    ApplicationMenu {
        id: appMenu
        visible: root.expanded
        width: root.contextWidth
        height: Math.min(root.contextHeight, Math.max(0, parent.height - 24))
        anchors { left: icons.right; leftMargin: 18; bottom: parent.bottom; bottomMargin: 10 }
        onActionTriggered: root.closeReveal()
    }
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeReveal(); event.accepted = true; }
    }
}
