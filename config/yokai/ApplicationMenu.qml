import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets

ColumnLayout {
    id: root
    property var trayItem: null
    property var levels: []
    readonly property var current: levels[levels.length - 1] ?? null
    readonly property var entriesModel: current?.opener.children ?? null
    readonly property var items: entriesModel?.values ?? []
    // Unloaded handles expose the native shared empty model; loaded empty
    // menus expose their own model, so they can still show an empty state.
    readonly property bool loading: current !== null && entriesModel === unloadedMenu.children
    readonly property real rowsHeight: items.reduce((total, item) => total + (item.isSeparator ? 10 : 32), 0)
    readonly property real rowsWidth: items.reduce((widest, item) => item.isSeparator ? widest : Math.max(widest,
        rowMetrics.advanceWidth(item.text.replace(/&/g, "")) + 44 + (item.icon !== "" ? 26 : 0) + (item.hasChildren ? 12 : 0)), 160)
    property real settledRowsHeight: 32
    property real settledRowsWidth: 160
    readonly property real naturalHeight: header.implicitHeight + settledRowsHeight + spacing
    readonly property real naturalWidth: Math.max(settledRowsWidth,
        titleMetrics.advanceWidth(current?.label ?? "") + 28 + header.spacing + (levels.length > 1 ? 30 + header.spacing : 0))
    implicitWidth: naturalWidth
    signal actionTriggered()
    spacing: 12
    function settleSize() {
        if (current && !loading) {
            settledRowsHeight = Math.max(32, rowsHeight);
            settledRowsWidth = rowsWidth;
        }
    }
    onRowsHeightChanged: settleTimer.restart()
    onRowsWidthChanged: settleTimer.restart()
    onLoadingChanged: settleTimer.restart()
    onCurrentChanged: settleTimer.restart()
    function clear() {
        const previous = levels;
        levels = [];
        // Each parent stays open while its submenu is in use. Release deepest first.
        for (let index = previous.length - 1; index >= 0; index--) {
            previous[index].opener.menu = null;
            previous[index].opener.destroy();
        }
    }
    function enter(handle, label) {
        const opener = menuFactory.createObject(root, {menu: handle});
        levels = [...levels, {opener: opener, label: label}];
        entries.positionViewAtBeginning();
    }
    function back() {
        if (levels.length < 2) return;
        const previous = levels[levels.length - 1];
        levels = levels.slice(0, -1);
        previous.opener.menu = null;
        previous.opener.destroy();
        entries.positionViewAtBeginning();
    }
    onTrayItemChanged: {
        clear();
        if (trayItem?.hasMenu) enter(trayItem.menu, Tray.displayName(trayItem));
        else { settledRowsHeight = 32; settledRowsWidth = 160; }
    }
    QsMenuOpener { id: unloadedMenu }
    FontMetrics { id: rowMetrics; font.family: "Inter"; font.pixelSize: 13 }
    FontMetrics { id: titleMetrics; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium }
    Timer { id: settleTimer; interval: 0; onTriggered: root.settleSize() }
    Component { id: menuFactory; QsMenuOpener {} }
    RowLayout {
        id: header
        Layout.fillWidth: true
        YokaiButton { visible: root.levels.length > 1; text: "‹"; implicitWidth: 30; onClicked: root.back() }
        TextLabel { text: root.current?.label ?? ""; font.pixelSize: 14; font.weight: Font.Medium; Layout.fillWidth: true }
        CloseButton { onClicked: root.trayItem = null }
    }
    ListView {
        id: entries
        Layout.fillWidth: true; Layout.fillHeight: true
        implicitHeight: contentHeight
        clip: true
        model: root.entriesModel
        TextLabel {
            anchors.centerIn: parent
            text: root.loading ? "Loading…" : "No menu items"
            color: Theme.muted
            font.pixelSize: 12
            visible: root.loading || root.items.length === 0
        }
        delegate: AbstractButton {
            id: entry
            required property var modelData
            width: entries.width
            height: modelData.isSeparator ? 10 : 32
            enabled: !modelData.isSeparator && modelData.enabled
            hoverEnabled: true
            background: Rectangle {
                color: entry.hovered ? Theme.elevated : "transparent"
                radius: 4
                Rectangle { visible: entry.modelData.isSeparator; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Theme.border }
            }
            contentItem: RowLayout {
                visible: !entry.modelData.isSeparator
                spacing: 10
                TextLabel {
                    Layout.preferredWidth: 16
                    text: entry.modelData.checkState === Qt.Checked ? (entry.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓") : ""
                    color: Theme.vermilion; font.pixelSize: 12
                }
                IconImage { visible: entry.modelData.icon !== ""; implicitSize: 16; source: entry.modelData.icon }
                TextLabel { text: entry.modelData.text.replace(/&/g, ""); color: entry.enabled ? Theme.ivory : Theme.muted; font.pixelSize: 13; Layout.fillWidth: true }
                TextLabel { text: entry.modelData.hasChildren ? "›" : ""; color: Theme.muted; font.pixelSize: 16 }
            }
            onClicked: {
                if (modelData.hasChildren) root.enter(modelData, modelData.text.replace(/&/g, ""));
                else { modelData.triggered(); root.actionTriggered(); }
            }
        }
        ScrollBar.vertical: ScrollBar {}
    }
}
