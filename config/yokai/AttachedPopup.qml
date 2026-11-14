import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: root
    readonly property MenuAnchor anchor: MenuAnchor {}
    visible: false
    screen: anchor.window?.screen ?? null
    anchors { left: true; top: true }
    margins { left: anchor.rect.x; top: anchor.rect.y }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "yokai-popup"
    WlrLayershell.keyboardFocus: visible && !closing && !Desktop.screenshotActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    default property alias popupContents: revealContent.data
    property string heading: ""
    property color surfaceColor: Theme.surface
    property bool surfaceVisible: true
    property bool connected: true
    property real neckTop: 12
    property real neckHeight: 22
    property bool resizeFromBottom: false
    property bool dismissOnOutsideClick: true
    property real surfaceColumnWidth: 0
    property real surfaceSideTop: 0
    property real surfaceSideHeight: 0
    property real targetWidth: implicitWidth
    property real targetHeight: implicitHeight
    readonly property real frameTargetHeight: Math.min(implicitHeight, Math.max(targetHeight, connected ? neckHeight + 16 : 0))
    property real revealedWidth: 14
    property real revealedHeight: 42
    property real revealedTop: 0
    property real contentOpacity: 0
    property bool resizeHorizontally: false
    property real openingWidth: 0
    property real openingHeight: 0
    property bool hoverClosing: false
    readonly property bool openingReveal: opening.running
    readonly property bool closing: closingReveal.running
    readonly property bool resizing: resizeReveal.running
    readonly property bool transitioning: openingReveal || closing || resizing || resizeDelay.running
    readonly property real viewportTop: resizeFromBottom ? Math.max(0, implicitHeight - revealedHeight) : revealedTop
    readonly property real seedHeight: Math.min(frameTargetHeight, connected ? neckHeight + 20 : 42)
    readonly property real seedTop: Math.max(0, Math.min(implicitHeight - seedHeight, neckTop - 10))
    color: "transparent"
    mask: Region {
        item: root.surfaceColumnWidth > 0 ? columnMask : revealViewport
        Region { item: root.surfaceColumnWidth > 0 ? sideMask : null }
    }
    function openReveal() {
        closingReveal.stop();
        resizeReveal.stop();
        opening.stop();
        openingWidth = targetWidth;
        openingHeight = frameTargetHeight;
        revealedWidth = 14;
        revealedHeight = seedHeight;
        revealedTop = seedTop;
        contentOpacity = 0;
        opening.restart();
    }
    function showReveal() {
        hoverClosing = false;
        if (visible) {
            if (closing) {
                closingReveal.stop();
                contentOpacity = 1;
                resizeTargetChanged();
            }
            return;
        }
        // Freeze the initial window size before mapping it; later target
        // changes resize from the current revealed size after opening.
        openReveal();
        visible = true;
    }
    function closeReveal(immediately = false) {
        hoverClosing = false;
        if (!visible) return;
        if (immediately) { visible = false; return; }
        if (closing) return;
        opening.stop();
        resizeReveal.stop();
        resizeDelay.stop();
        closingReveal.restart();
    }
    function closeFromHover() {
        if (Desktop.screenshotActive) return;
        closeReveal();
        hoverClosing = closing;
    }
    function resizeContents() {
        if (!visible || openingReveal || closing || resizing) return;
        resizeHorizontally = Math.abs(revealedWidth - targetWidth) > 0.5;
        if (!resizeHorizontally && Math.abs(revealedHeight - frameTargetHeight) < 0.5 && Math.abs(revealedTop) < 0.5) return;
        resizeReveal.restart();
    }
    function resizeTargetChanged() {
        if (!visible || openingReveal || closing) return;
        // Start at the current size when a new target arrives mid-transition.
        resizeReveal.stop();
        resizeDelay.restart();
    }
    onTargetWidthChanged: resizeTargetChanged()
    onFrameTargetHeightChanged: resizeTargetChanged()
    onWidthChanged: resizeDelay.restart()
    onHeightChanged: resizeDelay.restart()
    data: [
        Item {
            id: columnMask
            y: root.viewportTop
            width: Math.min(root.revealedWidth, root.surfaceColumnWidth)
            height: root.revealedHeight
        },
        Item {
            id: sideMask
            x: root.surfaceColumnWidth
            y: root.viewportTop + root.surfaceSideTop
            width: Math.max(0, root.revealedWidth - root.surfaceColumnWidth)
            height: root.surfaceSideHeight
        },
        Item {
            id: revealViewport
            width: root.revealedWidth
            height: root.revealedHeight
            y: root.viewportTop
            clip: true
            DockShape {
                visible: root.surfaceVisible
                anchors.fill: parent
                fillColor: root.surfaceColor
                connected: root.connected
                columnWidth: root.surfaceColumnWidth
                sideTop: root.surfaceSideTop
                sideHeight: root.surfaceSideHeight
                neckTop: root.neckTop - revealViewport.y
                neckHeight: root.neckHeight
            }
            Item {
                id: revealContent
                width: root.targetWidth
                height: root.revealedHeight
                opacity: root.contentOpacity
                enabled: !root.closing
            }
        },
        SequentialAnimation {
            id: opening
            NumberAnimation { target: root; property: "revealedWidth"; to: root.openingWidth; duration: 120; easing.type: Easing.OutCubic }
            ParallelAnimation {
                NumberAnimation { target: root; property: "revealedTop"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "revealedHeight"; to: root.openingHeight; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "contentOpacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
            }
            onFinished: root.resizeContents()
        },
        SequentialAnimation {
            id: closingReveal
            ParallelAnimation {
                NumberAnimation { target: root; property: "revealedTop"; to: root.seedTop; duration: 180; easing.type: Easing.InOutCubic }
                NumberAnimation { target: root; property: "revealedHeight"; to: root.seedHeight; duration: 180; easing.type: Easing.InOutCubic }
                NumberAnimation { target: root; property: "contentOpacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
            }
            NumberAnimation { target: root; property: "revealedWidth"; to: 14; duration: 120; easing.type: Easing.InOutCubic }
            onFinished: root.visible = false
        },
        SequentialAnimation {
            id: resizeReveal
            NumberAnimation { target: root; property: "revealedWidth"; to: root.targetWidth; duration: root.resizeHorizontally ? 120 : 0; easing.type: Easing.OutCubic }
            ParallelAnimation {
                NumberAnimation { target: root; property: "revealedTop"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "revealedHeight"; to: root.frameTargetHeight; duration: 180; easing.type: Easing.OutCubic }
            }
            onFinished: root.resizeContents()
        },
        Timer { id: resizeDelay; interval: 0; onTriggered: root.resizeContents() },
        HyprlandFocusGrab {
            windows: [root, root.anchor.window]
            active: root.dismissOnOutsideClick && root.visible && !root.closing && !Desktop.screenshotActive
            onCleared: if (!Desktop.screenshotActive) root.closeReveal()
        },
        Connections {
            target: root
            function onVisibleChanged() {
                if (root.visible) {
                    Desktop.close();
                    if (Desktop.panelMenu && Desktop.panelMenu !== root) Desktop.panelMenu.closeReveal(true);
                    Desktop.panelMenu = root;
                    if (!root.openingReveal) root.openReveal();
                } else {
                    opening.stop();
                    resizeReveal.stop();
                    closingReveal.stop();
                    resizeDelay.stop();
                    root.hoverClosing = false;
                    if (Desktop.panelMenu === root) Desktop.panelMenu = null;
                }
            }
        }
    ]
}
