import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Networking
import Quickshell.Bluetooth

PanelWindow {
    id: root
    readonly property real groupMargin: 6
    anchors { left: true; top: true; bottom: true }
    implicitWidth: Theme.railWidth
    color: Theme.voidColor
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Theme.railWidth
    WlrLayershell.namespace: "yokai-rail"
    WlrLayershell.keyboardFocus: Desktop.panelMenu?.anchor.window === root && Desktop.panelMenu.visible && !Desktop.screenshotActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    contentItem.focus: true
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && Desktop.panelMenu?.anchor.window === root) {
            Desktop.panelMenu.closeReveal();
            event.accepted = true;
        }
    }
    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) ?? null
    readonly property var ethernetDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wired && device.nmManaged)
    readonly property var ethernetDevice: ethernetDevices.find(device => device.connected)
        ?? ethernetDevices.find(device => device.hasLink) ?? ethernetDevices[0] ?? null
    property var workspacePreviewButton: null
    property string workspacePreviewAddress: ""
    ListModel { id: workspaceRows }
    function syncWorkspaceButtons() {
        const available = Compositor.visibleWorkspaces.filter(workspace => workspace.monitor === root.screen?.name);
        for (let index = workspaceRows.count - 1; index >= 0; index--) {
            if (!available.some(workspace => String(workspace.address) === workspaceRows.get(index).workspaceAddress))
                workspaceRows.remove(index);
        }
        for (let index = 0; index < available.length; index++) {
            const workspace = available[index];
            const address = String(workspace.address);
            let row = -1;
            for (let candidate = 0; candidate < workspaceRows.count; candidate++) {
                if (workspaceRows.get(candidate).workspaceAddress === address) { row = candidate; break; }
            }
            if (row < 0) workspaceRows.insert(index, {workspaceAddress: address, workspaceFocused: Boolean(workspace.focused)});
            else {
                if (row !== index) workspaceRows.move(row, index, 1);
                workspaceRows.setProperty(index, "workspaceFocused", Boolean(workspace.focused));
            }
        }
        checkWorkspacePreviewHover();
    }
    Component.onCompleted: Qt.callLater(root.syncWorkspaceButtons)
    onScreenChanged: Qt.callLater(root.syncWorkspaceButtons)
    Connections {
        target: Compositor
        function onVisibleWorkspacesChanged() { Qt.callLater(root.syncWorkspaceButtons); }
    }
    Connections {
        target: Desktop
        function onPanelMenuChanged() {
            if (Desktop.panelMenu && Desktop.panelMenu !== workspacePreview) workspacePreviewOpen.stop();
        }
    }
    function queueWorkspacePreview(button) {
        workspacePreviewButton = button;
        workspacePreviewAddress = button.workspaceAddress;
        workspacePreviewClose.stop();
        if (LockScreen.locked || Desktop.opened) return;
        if (workspacePreview.visible) openWorkspacePreview();
        else workspacePreviewOpen.restart();
    }
    function openWorkspacePreview() {
        const button = workspacePreviewButton;
        if (!button?.hovered || LockScreen.locked || Desktop.opened) return;
        workspacePreview.workspaceAddress = workspacePreviewAddress;
        positionWorkspacePreview();
        workspacePreview.showReveal();
    }
    function positionWorkspacePreview() {
        const button = workspacePreviewButton;
        if (!button) return;
        const point = button.mapToItem(root.contentItem, 0, 0);
        const centered = point.y + (button.height - workspacePreview.height) / 2;
        workspacePreview.anchor.rect.y = Math.max(8, Math.min(centered, root.height - workspacePreview.height - 8));
    }
    function checkWorkspacePreviewHover() {
        if (!workspacePreview.visible) { workspacePreviewClose.stop(); return; }
        if (workspacePreviewButton?.hovered || workspacePreview.hovered) {
            workspacePreviewClose.stop();
            if (workspacePreview.closing && workspacePreview.hoverClosing) workspacePreview.showReveal();
        } else if (workspacePreview.transitioning) workspacePreviewClose.stop();
        else workspacePreviewClose.restart();
    }
    function positionMenu(menu, group) {
        const point = group.mapToItem(root.contentItem, 0, 0);
        const y = Math.max(12, Math.min(point.y + group.height + 8 - menu.height, root.height - menu.height - 4));
        menu.anchor.rect.y = y;
        menu.neckTop = point.y - y;
        menu.neckHeight = menu.connected ? group.height : 0;
    }
    function showMenu(menu, group) {
        Desktop.close();
        trayClose.stop();
        notificationClose.stop();
        workspacePreviewOpen.stop();
        workspacePreviewClose.stop();
        for (const other of [hostNetworkMenu, hubMenu, updatesMenu, outputMenu, inputMenu, hostAudioMenu, wifiMenu, ethernetMenu, bluetoothMenu, trayPopup, calendarPopup, nightMenu, notificationMenu, workspacePreview]) {
            if (other !== menu) other.closeReveal(true);
        }
        positionMenu(menu, group);
        if (menu.visible && !menu.closing) menu.closeReveal();
        else menu.showReveal();
    }
    function positionTray() {
        positionMenu(trayPopup, trayGroup);
    }
    function openTray() { trayClose.stop(); positionTray(); trayPopup.showReveal(); }
    function checkTrayHover() {
        if (!trayPopup.visible) { trayClose.stop(); return; }
        if (trayButton.hovered || trayPopup.hovered) {
            trayClose.stop();
            if (trayPopup.closing && trayPopup.hoverClosing) trayPopup.showReveal();
        } else if (trayPopup.transitioning) trayClose.stop();
        else trayClose.restart();
    }
    function openNotifications() { notificationClose.stop(); positionMenu(notificationMenu, notificationGroup); notificationMenu.showReveal(); }
    function checkNotificationHover() {
        if (!notificationMenu.visible) { notificationClose.stop(); return; }
        if (notificationHover.hovered || notificationMenu.hovered) {
            notificationClose.stop();
            if (notificationMenu.closing && notificationMenu.hoverClosing) notificationMenu.showReveal();
        } else if (notificationMenu.transitioning) notificationClose.stop();
        else notificationClose.restart();
    }
    Timer { id: trayClose; interval: 300; onTriggered: if (!trayButton.hovered && !trayPopup.hovered && !trayPopup.transitioning) trayPopup.closeFromHover() }
    Timer { id: notificationClose; interval: 300; onTriggered: if (!notificationHover.hovered && !notificationMenu.hovered && !notificationMenu.transitioning) notificationMenu.closeFromHover() }
    Timer { id: workspacePreviewOpen; interval: 180; onTriggered: root.openWorkspacePreview() }
    Timer {
        id: workspacePreviewClose
        interval: 300
        onTriggered: if (!root.workspacePreviewButton?.hovered && !workspacePreview.hovered && !workspacePreview.transitioning) workspacePreview.closeFromHover()
    }
    WorkspacePreviewMenu {
        id: workspacePreview
        anchor.window: root
        anchor.rect.x: root.width + 10
        onHoveredChanged: root.checkWorkspacePreviewHover()
        onTransitioningChanged: root.checkWorkspacePreviewHover()
        onHeightChanged: if (visible) root.positionWorkspacePreview()
    }
    HubMenu {
        id: hubMenu
        connected: true
        heading: "Desktop"
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    UpdatesMenu {
        id: updatesMenu
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHeightChanged: if (visible) root.positionMenu(updatesMenu, updatesGroup)
    }
    Connections {
        target: Desktop
        function onUpdatesRequested() {
            if (!Updates.enabled || root.screen !== Theme.railScreens[0]) return;
            Desktop.close();
            root.positionMenu(updatesMenu, updatesGroup);
            updatesMenu.showReveal();
        }
    }
    PanelMenu {
        id: hostAudioMenu
        heading: hostAudioContent.item?.heading ?? "Audio"
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        implicitHeight: Math.min(maximumHeight, (hostAudioContent.item?.implicitHeight ?? 0) + 80)
        onHeightChanged: if (visible) root.positionMenu(hostAudioMenu, audioGroup)
        Loader {
            id: hostAudioContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property url widgetSource: hostAudioWidget.item?.settingsSource ?? ""
            onWidgetSourceChanged: {
                if (widgetSource.toString() !== "") setSource(widgetSource, {theme: Theme});
                else source = "";
            }
            onLoaded: item.menuOpen = Qt.binding(() => hostAudioMenu.visible)
        }
    }
    AudioMenu {
        id: outputMenu
        microphone: false
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHeightChanged: if (visible) root.positionMenu(outputMenu, audioGroup)
    }
    AudioMenu {
        id: inputMenu
        microphone: true
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHeightChanged: if (visible) root.positionMenu(inputMenu, audioGroup)
    }
    PanelMenu {
        id: hostNetworkMenu
        heading: hostNetworkContent.item?.heading ?? "Network"
        fitContents: true
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHeightChanged: if (visible) root.positionMenu(hostNetworkMenu, networkGroup)
        Loader {
            id: hostNetworkContent
            Layout.fillWidth: true
            Layout.preferredHeight: item?.implicitHeight ?? 0
            readonly property url widgetSource: hostNetworkWidget.item?.settingsSource ?? ""
            onWidgetSourceChanged: {
                if (widgetSource.toString() !== "") setSource(widgetSource, {theme: Theme});
                else source = "";
            }
        }
    }
    WifiMenu {
        id: wifiMenu
        device: root.wifiDevice
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    EthernetMenu {
        id: ethernetMenu
        device: root.ethernetDevice
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    BluetoothMenu {
        id: bluetoothMenu
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    TrayPanel {
        id: trayPopup
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHeightChanged: if (visible) root.positionTray()
        onHoveredChanged: root.checkTrayHover()
        onTransitioningChanged: root.checkTrayHover()
    }
    CalendarMenu {
        id: calendarPopup
        today: clock.date
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    NightLightMenu {
        id: nightMenu
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
    }
    NotificationMenu {
        id: notificationMenu
        anchor.window: root
        anchor.rect.x: root.width - root.groupMargin - 2
        onHoveredChanged: root.checkNotificationHover()
        onTransitioningChanged: root.checkNotificationHover()
    }
    RailOrnament { anchors.fill: parent; z: -1 }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.border }
    SystemClock { id: clock; precision: SystemClock.Seconds }
    Item {
        id: hubGroup
        anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: root.groupMargin; rightMargin: root.groupMargin; topMargin: 20 }
        implicitHeight: 44
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 8
            color: Theme.surface
            visible: hubMenu.visible
            z: -1
        }
        IconButton {
            id: hubButton
            anchors.fill: parent
            iconSource: Qt.resolvedUrl("assets/kitsune-icon.svg")
            iconSize: 44
            iconColor: "transparent"
            background: Item {}
            property real hoverAmount: hovered || activeFocus ? 1 : 0
            property real pressGlow: 0
            Behavior on hoverAmount { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            onPressed: { pressGlow = 1; pressGlowDecay.restart(); }
            NumberAnimation {
                id: pressGlowDecay
                target: hubButton; property: "pressGlow"
                to: 0; duration: 360; easing.type: Easing.OutCubic
            }
            contentItem: Item {
                Item {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -hubButton.hoverAmount
                    width: hubButton.iconSize
                    height: hubButton.iconSize
                    scale: hubButton.down ? .92 : 1 + hubButton.hoverAmount * .05
                    rotation: -4 * hubButton.hoverAmount
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    IconImage {
                        anchors.fill: parent
                        source: hubButton.iconSource
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: Theme.vermilion
                            shadowEnabled: true
                            shadowColor: Theme.vermilion
                            shadowBlur: .8
                            blurMax: 12
                            shadowScale: 1.1
                            shadowOpacity: Math.min(1, hubButton.hoverAmount * .7 + hubButton.pressGlow * .65)
                            shadowHorizontalOffset: 0
                            shadowVerticalOffset: 0
                        }
                    }
                    Image {
                        anchors.fill: parent
                        source: hubButton.iconSource
                        sourceSize: Qt.size(hubButton.iconSize * 4, hubButton.iconSize * 4)
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }
            onClicked: root.showMenu(hubMenu, hubGroup)
        }
    }
    RailGroup {
        id: notificationGroup
        anchors { top: clockGroup.bottom; left: parent.left; right: parent.right; leftMargin: root.groupMargin; rightMargin: root.groupMargin; topMargin: 10 }
        joined: notificationMenu.visible
        HoverHandler { id: notificationHover; onHoveredChanged: if (hovered) root.openNotifications(); else root.checkNotificationHover() }
        IconButton {
            Layout.fillWidth: true
            iconName: NotificationCenter.quiet ? "notifications-disabled-symbolic" : "preferences-system-notifications-symbolic"
            iconSize: Theme.railIconSize
            iconColor: Theme.ivory
            onClicked: root.openNotifications()
            Rectangle { visible: NotificationCenter.unread > 0; width: 5; height: 5; radius: 3; color: Theme.vermilion; anchors { top: parent.top; right: parent.right; topMargin: 3; rightMargin: 3 } }
        }
    }
    RailGroup {
        id: updatesGroup
        visible: Updates.enabled
        height: visible ? implicitHeight : 0
        anchors { top: notificationGroup.bottom; left: parent.left; right: parent.right; leftMargin: root.groupMargin; rightMargin: root.groupMargin; topMargin: visible ? 10 : 0 }
        joined: updatesMenu.visible
        IconButton {
            id: updatesButton
            Layout.fillWidth: true
            iconName: "software-update-available-symbolic"
            iconSize: Theme.railIconSize
            iconColor: Theme.ivory
            onClicked: root.showMenu(updatesMenu, updatesGroup)
            Rectangle {
                id: updateBadge
                visible: Updates.failed || Updates.hasUpdates || Updates.ready || Updates.running || Boolean(Updates.state.pendingBoot)
                width: 5; height: 5; radius: 3; color: Theme.vermilion
                anchors { top: parent.top; right: parent.right; topMargin: 3; rightMargin: 3 }
                SequentialAnimation on opacity {
                    running: Updates.running
                    loops: Animation.Infinite
                    NumberAnimation { to: .25; duration: 900 }
                    NumberAnimation { to: 1; duration: 900 }
                    onStopped: updateBadge.opacity = 1
                }
            }
        }
    }
    ColumnLayout {
        id: clockGroup
        anchors { top: hubGroup.bottom; left: parent.left; right: parent.right; topMargin: 10; leftMargin: root.groupMargin; rightMargin: root.groupMargin }
        spacing: 10
        RailGroup {
            id: timeGroup
            Layout.fillWidth: true
            horizontalPadding: 2
            TextLabel {
                text: Qt.formatDateTime(clock.date, "HH\nmm\nss")
                color: Theme.white
                font.family: "Inter"; font.pixelSize: 16; font.weight: Font.Light
                font.features: ({ "tnum": 1 })
                lineHeight: 1.05
                horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true
            }
        }
        RailGroup {
            id: dateGroup
            Layout.fillWidth: true
            horizontalPadding: 0
            joined: calendarPopup.visible
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { acceptedButtons: Qt.LeftButton; onTapped: root.showMenu(calendarPopup, dateGroup) }
            TextLabel {
                text: clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd\ndd\nMMM").toUpperCase()
                color: Theme.white
                font.family: "Inter"; font.pixelSize: 16; font.weight: Font.Light
                font.features: ({ "tnum": 1 })
                lineHeight: 1.05
                horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true
            }
        }
    }
    Column {
        id: workspaceGroup
        anchors { left: parent.left; right: parent.right; leftMargin: 2; rightMargin: 2 }
        y: (updatesGroup.y + updatesGroup.height + bottomGroup.y - height) / 2
        spacing: 6
        onYChanged: if (workspacePreview.visible) Qt.callLater(root.positionWorkspacePreview)
        onHeightChanged: if (workspacePreview.visible) Qt.callLater(root.positionWorkspacePreview)
        Repeater {
            model: workspaceRows
            AbstractButton {
                id: workspaceButton
                required property string workspaceAddress
                required property bool workspaceFocused
                width: workspaceGroup.width
                implicitHeight: 40
                hoverEnabled: true
                contentItem: TextLabel {
                    text: workspaceButton.workspaceAddress
                    font.family: "JetBrains Mono"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    color: workspaceButton.workspaceFocused ? Theme.ivory : Theme.muted
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: workspaceButton.hovered ? Theme.elevated : "transparent"
                    radius: 4
                    Rectangle { width: 28; height: 28; radius: 14; anchors.centerIn: parent; color: "transparent"; border.width: 1; border.color: Theme.vermilion; visible: workspaceButton.workspaceFocused }
                }
                onHoveredChanged: {
                    if (hovered) root.queueWorkspacePreview(workspaceButton);
                    else root.checkWorkspacePreviewHover();
                }
                onClicked: {
                    workspacePreviewOpen.stop();
                    workspacePreviewClose.stop();
                    workspacePreview.closeReveal();
                    Compositor.focusWorkspace(workspaceAddress);
                }
            }
        }
    }
    ColumnLayout {
        id: bottomGroup
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: root.groupMargin; rightMargin: root.groupMargin; bottomMargin: 12 }
        spacing: 10
        RailGroup {
            id: trayGroup
            Layout.fillWidth: true
            joined: trayPopup.visible
            IconButton {
                id: trayButton
                Layout.fillWidth: true
                iconName: "view-grid-symbolic"
                iconSize: Theme.railIconSize
                iconColor: Theme.ivory
                onHoveredChanged: if (hovered) root.openTray(); else root.checkTrayHover()
                onClicked: root.openTray()
            }
        }
        RailGroup {
            id: nightGroup
            Layout.fillWidth: true
            joined: nightMenu.visible
            IconButton {
                Layout.fillWidth: true
                iconName: NightLight.enabled ? "weather-clear-symbolic" : "night-light-symbolic"
                iconSize: Theme.railIconSize
                iconColor: Theme.ivory
                onClicked: if (!NightLight.busy) NightLight.toggle()
                onContextMenuRequested: root.showMenu(nightMenu, nightGroup)
            }
        }
        RailGroup {
            id: layoutGroup
            Layout.fillWidth: true
            horizontalPadding: 0
            TextLabel {
                text: Compositor.keyboardLayoutShort
                font.family: "JetBrains Mono"; font.pixelSize: 14; font.weight: Font.Medium
                color: Theme.ivory
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Layout.fillWidth: true; Layout.preferredHeight: 24
            }
        }
        RailGroup {
            id: audioGroup
            Layout.fillWidth: true
            joined: outputMenu.visible || inputMenu.visible || hostAudioMenu.visible
            RailAudio { id: microphoneButton; Layout.fillWidth: true; microphone: true; onSettingsRequested: root.showMenu(inputMenu, audioGroup) }
            Loader {
                id: hostAudioWidget
                objectName: "host-audio-widget"
                Layout.fillWidth: true
                visible: widgetSource.toString() !== ""
                readonly property url widgetSource: Quickshell.env("YOKAI_AUDIO_WIDGET") || ""
                Component.onCompleted: if (visible) setSource(widgetSource, {theme: Theme, screen: root.screen})
            }
            Connections {
                target: hostAudioWidget.item
                ignoreUnknownSignals: true
                function onSettingsRequested() { root.showMenu(hostAudioMenu, audioGroup); }
            }
            RailAudio { id: outputButton; Layout.fillWidth: true; microphone: false; onSettingsRequested: root.showMenu(outputMenu, audioGroup) }
        }
        RailGroup {
            id: networkGroup
            Layout.fillWidth: true
            joined: wifiMenu.visible || ethernetMenu.visible || bluetoothMenu.visible || hostNetworkMenu.visible
            Loader {
                id: hostNetworkWidget
                objectName: "host-network-widget"
                Layout.fillWidth: true
                visible: widgetSource.toString() !== ""
                readonly property url widgetSource: Quickshell.env("YOKAI_NETWORK_WIDGET") || ""
                Component.onCompleted: {
                    if (visible) setSource(widgetSource, {theme: Theme});
                }
            }
            Connections {
                target: hostNetworkWidget.item
                ignoreUnknownSignals: true
                function onSettingsRequested() { root.showMenu(hostNetworkMenu, networkGroup); }
            }
            IconButton {
                id: bluetoothButton
                Layout.fillWidth: true
                iconName: Bluetooth.defaultAdapter?.enabled ? "bluetooth-active-symbolic" : "bluetooth-disabled-symbolic"
                iconSize: Theme.railIconSize
                iconColor: Theme.ivory
                onClicked: {
                    const adapter = Bluetooth.defaultAdapter;
                    if (adapter) adapter.enabled = !adapter.enabled;
                }
                onContextMenuRequested: root.showMenu(bluetoothMenu, networkGroup)
            }
            IconButton {
                id: wifiButton
                Layout.fillWidth: true
                iconName: !Networking.wifiEnabled ? "network-wireless-disabled-symbolic" : root.wifiDevice?.connected ? "network-wireless-signal-excellent-symbolic" : "network-wireless-offline-symbolic"
                iconSize: Theme.railIconSize
                iconColor: Theme.ivory
                onClicked: {
                    if (root.wifiDevice && Networking.wifiHardwareEnabled)
                        Networking.wifiEnabled = !Networking.wifiEnabled;
                }
                onContextMenuRequested: root.showMenu(wifiMenu, networkGroup)
            }
            IconButton {
                Layout.fillWidth: true
                iconName: root.ethernetDevice?.connected ? "network-wired-symbolic" : "network-wired-disconnected-symbolic"
                iconSize: Theme.railIconSize
                iconColor: Theme.ivory
                onClicked: ethernetMenu.toggleConnection()
                onContextMenuRequested: root.showMenu(ethernetMenu, networkGroup)
            }
        }
    }
}
