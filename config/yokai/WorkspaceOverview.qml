import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ScrollView {
    id: root
    contentWidth: availableWidth
    contentHeight: desktopGrid.implicitHeight
    clip: true
    readonly property int columns: 1
    readonly property real cardWidth: Math.max(180, Math.min(420, availableWidth))
    onColumnsChanged: Switcher.previewColumns = columns
    onCardWidthChanged: Switcher.previewWidth = cardWidth
    Component.onCompleted: { Switcher.previewColumns = columns; Switcher.previewWidth = cardWidth; }
    function reveal(index) {
        const height = Math.ceil(Switcher.previewHeight + Switcher.headerHeight);
        const y = Math.floor(index / columns) * (height + Switcher.previewRowGap);
        if (y < contentItem.contentY) contentItem.contentY = y;
        else if (y + height > contentItem.contentY + availableHeight) contentItem.contentY = Math.max(0, y + height - availableHeight);
    }
    Connections {
        target: Switcher
        function onSelectedChanged() {
            const index = Switcher.desktops.findIndex(desktop => desktop.windows.includes(Switcher.selectedWindow));
            if (index >= 0) root.reveal(index);
        }
    }
    GridLayout {
        id: desktopGrid
        width: root.columns * root.cardWidth + (root.columns - 1) * Switcher.previewColumnGap
        x: Math.max(0, (root.availableWidth - width) / 2)
        columns: root.columns
        columnSpacing: Switcher.previewColumnGap; rowSpacing: Switcher.previewRowGap
        Repeater {
            model: Switcher.desktopModel
            DesktopPreview { Layout.minimumWidth: root.cardWidth; Layout.maximumWidth: root.cardWidth; Layout.preferredHeight: Switcher.previewHeight + Switcher.headerHeight }
        }
    }
    TextLabel { visible: Switcher.desktops.length === 0; text: "No open windows"; color: Theme.muted }
}
