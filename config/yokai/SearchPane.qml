pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "Fuzzy.js" as Fuzzy

ColumnLayout {
    id: root
    signal focusWindows()
    spacing: 12
    readonly property bool clipboard: Desktop.mode === "clipboard"
    readonly property var searchModes: ["apps", "folders", "clipboard"]
    readonly property bool folders: Desktop.mode === "folders"
    readonly property bool searching: folders ? FolderSearch.busy : BrowserSearch.busy || TelegramSearch.busy
    readonly property var applications: Fuzzy.rankedApplications(Desktop.query, DesktopEntries.applications.values)
    readonly property var browserResults: !folders && Desktop.query.trim() !== "" && BrowserSearch.resultsQuery === Desktop.query ? BrowserSearch.results : []
    readonly property var telegramResults: !folders && Desktop.query.trim() !== "" && TelegramSearch.resultsQuery === Desktop.query ? TelegramSearch.results : []
    readonly property var resultEntries: folders ? FolderSearch.results.map(path => ({kind: "folder", id: path,
        title: path.split("/").pop() || path, description: path, icon: "folder-symbolic", path: path}))
        : applications.concat(browserResults, telegramResults).sort(Fuzzy.compareResults).slice(0, Desktop.query.trim() === "" ? applications.length : 80)
    property string selectedId: ""
    property string selectionQuery: ""
    property string selectionMode: ""
    property bool selectionInteracted: false

    function identity(result) { return result.kind + ":" + result.id; }

    function activate() {
        if ((Desktop.mode !== "apps" && Desktop.mode !== "folders") || selectionQuery !== Desktop.query || selectionMode !== Desktop.mode || BrowserSearch.opening || TelegramSearch.opening) return;
        const selected = resultEntries.find(result => identity(result) === selectedId);
        if (!selected) return;
        if (selected.kind === "folder") Desktop.openFolder(selected.path);
        else if (selected.kind === "browser") Desktop.openBrowserResult(selected);
        else if (selected.kind === "telegram") Desktop.openTelegramResult(selected);
        else Desktop.launchApplication(selected.app);
    }

    function chooseIndex(index) {
        const selected = resultEntries[index];
        selectedId = selected ? identity(selected) : "";
        results.currentIndex = selected ? index : -1;
    }

    function resetSelection() {
        selectionQuery = Desktop.query;
        selectionMode = Desktop.mode;
        selectionInteracted = false;
        chooseIndex(resultEntries.length > 0 ? 0 : -1);
        results.positionViewAtBeginning();
    }

    function reconcileSelection() {
        if (selectionQuery !== Desktop.query || selectionMode !== Desktop.mode) { resetSelection(); return; }
        if (!selectionInteracted) {
            chooseIndex(resultEntries.length > 0 ? 0 : -1);
            results.positionViewAtBeginning();
            return;
        }
        const index = resultEntries.findIndex(result => identity(result) === selectedId);
        chooseIndex(index >= 0 ? index : resultEntries.length > 0 ? 0 : -1);
    }

    function moveSelection(direction) {
        if (resultEntries.length === 0) return;
        selectionInteracted = true;
        const current = resultEntries.findIndex(result => identity(result) === selectedId);
        chooseIndex(Math.max(0, Math.min(resultEntries.length - 1, current + direction)));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }

    function setMode(mode) {
        Desktop.mode = mode;
        resetSelection();
        if (mode === "folders") FolderSearch.query = Desktop.query;
        if (mode === "clipboard") Qt.callLater(clipboardPane.focusSearch);
        else search.forceActiveFocus();
    }
    function cycleMode(direction) {
        const index = Math.max(0, searchModes.indexOf(Desktop.mode));
        setMode(searchModes[(index + direction + searchModes.length) % searchModes.length]);
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 38
        radius: 10
        color: "#18000000"
        border.color: "#18FFFFFF"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 3
            Repeater {
                model: ["All", "Folders", "Clipboard"]
                Button {
                    id: modeButton
                    required property string modelData
                    required property int index
                    readonly property bool selected: Desktop.mode === root.searchModes[index]
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: root.setMode(root.searchModes[index])
                    background: Rectangle {
                        radius: 7
                        color: modeButton.selected ? "#24FFFFFF" : modeButton.hovered ? "#10FFFFFF" : "transparent"
                    }
                    contentItem: TextLabel {
                        text: modeButton.modelData
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 14
                        font.weight: modeButton.selected ? Font.DemiBold : Font.Normal
                        color: modeButton.selected ? Theme.ivory : Theme.muted
                    }
                }
            }
        }
    }

    TextField {
        id: search
        visible: !root.clipboard
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        leftPadding: 42
        rightPadding: 14
        font.family: "Inter"
        font.pixelSize: 15
        color: Theme.ivory
        placeholderTextColor: Theme.muted
        selectionColor: Theme.selection
        selectedTextColor: Theme.ivory
        text: Desktop.query
        placeholderText: root.folders ? "Find a folder…" : TelegramSearch.enabled ? "Search apps, websites and chats…" : "Search apps and websites…"
        selectByMouse: true
        background: Rectangle {
            radius: 10
            color: "#20000000"
            border.color: search.activeFocus ? "#A6D92B3A" : "#20FFFFFF"
        }
        IconImage {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            implicitSize: 18
            source: Quickshell.iconPath("edit-find-symbolic", "system-search")
            opacity: .65
        }
        onActiveFocusChanged: if (activeFocus && Desktop.mode === "windows") Desktop.mode = "apps"
        onTextChanged: {
            Desktop.query = text;
            if (root.folders) FolderSearch.query = text;
        }
        onAccepted: root.activate()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.cycleMode(event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? -1 : 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                Desktop.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1);
                event.accepted = true;
            }
        }
    }

    ClipboardPane {
        id: clipboardPane
        visible: root.clipboard
        Layout.fillWidth: true
        Layout.fillHeight: true
        onCycleMode: direction => root.cycleMode(direction)
    }

    YokaiButton {
        visible: !root.clipboard && !root.folders && TelegramSearch.enabled && !TelegramSearch.ready
        Layout.alignment: Qt.AlignLeft
        implicitHeight: 28
        text: "Connect Telegram"
        onClicked: TelegramSearch.showSetup(Desktop.screen)
    }

    Item {
        visible: !root.clipboard
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true

        ListView {
            id: results
            anchors.fill: parent
            clip: true
            spacing: 3
            model: root.resultEntries
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            onCountChanged: {
                if (count === 0) currentIndex = -1;
                else if (currentIndex < 0 || currentIndex >= count) currentIndex = 0;
            }
            delegate: Rectangle {
                id: result
                required property var modelData
                required property int index
                readonly property bool selected: root.selectedId === root.identity(modelData) && Desktop.mode !== "windows"
                width: results.width
                height: 56
                radius: 9
                color: selected ? "#24FFFFFF" : pointer.containsMouse ? "#10FFFFFF" : "transparent"

                Rectangle {
                    visible: result.selected
                    width: 3
                    height: 22
                    radius: 1.5
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.vermilion
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    IconImage {
                        implicitSize: 28
                        source: Quickshell.iconPath(result.modelData.icon, "application-x-executable")
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        TextLabel {
                            Layout.fillWidth: true
                            text: result.modelData.title
                            font.pixelSize: 14
                            font.weight: result.selected ? Font.DemiBold : Font.Normal
                        }
                        TextLabel {
                            Layout.fillWidth: true
                            text: result.modelData.description
                            visible: text.length > 0
                            color: Theme.muted
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        visible: result.modelData.kind !== "folder"
                        Layout.preferredWidth: sourceLabel.implicitWidth + 12
                        Layout.preferredHeight: 19
                        radius: 4
                        color: "#18202024"
                        border.color: Theme.border
                        TextLabel { id: sourceLabel; anchors.centerIn: parent; text: result.modelData.sourceLabel ?? ""; color: Theme.muted; font.pixelSize: 10 }
                    }
                }
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectionInteracted = true;
                        root.chooseIndex(result.index);
                        root.activate();
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {
                id: resultScrollBar
                width: 3
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 3
                    radius: 1.5
                    color: "#60FFFFFF"
                    opacity: resultScrollBar.active ? 1 : .4
                }
                background: Item {}
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 24)
            spacing: 6
            visible: results.count === 0
            TextLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.searching ? root.folders ? "Searching folders…" : "Searching…" : root.folders && FolderSearch.error ? "Could not search folders" : "No results"
                font.pixelSize: 14
            }
            TextLabel {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                text: root.searching ? root.folders ? "Looking for matching folders" : TelegramSearch.enabled ? "Searching apps, websites and chats" : "Searching apps and websites"
                    : root.folders && FolderSearch.error ? FolderSearch.error
                    : !root.folders && Desktop.query.trim() !== "" && !BrowserSearch.ready ? "Browser history is not connected"
                    : !root.folders && BrowserSearch.error !== "" ? BrowserSearch.error : "Try a different search"
                color: Theme.muted
                font.pixelSize: 12
            }
        }
    }

    TextLabel {
        Layout.fillWidth: true
        visible: !root.clipboard && (root.folders ? root.searching && results.count > 0 : BrowserSearch.openError !== "" || TelegramSearch.openError !== "" || BrowserSearch.opening || TelegramSearch.opening || TelegramSearch.searchError !== "" || root.searching && results.count > 0)
        text: root.folders ? "Searching folders…" : BrowserSearch.openError || TelegramSearch.openError || (BrowserSearch.opening ? "Opening page…" : TelegramSearch.opening ? "Opening chat…" : TelegramSearch.searchError || (TelegramSearch.enabled && TelegramSearch.ready ? "Searching websites and chats…" : "Searching websites…"))
        color: Theme.muted
        font.pixelSize: 11
    }

    Connections {
        target: Desktop
        function onQueryChanged() { root.resetSelection(); Qt.callLater(root.reconcileSelection); }
        function onModeChanged() {
            if (Desktop.mode === "apps" || Desktop.mode === "folders") {
                root.resetSelection();
                if (root.folders) FolderSearch.query = Desktop.query;
                search.forceActiveFocus();
            } else if (Desktop.mode === "clipboard") {
                Qt.callLater(clipboardPane.focusSearch);
            } else if (Desktop.mode === "windows") {
                search.focus = false;
                root.focusWindows();
            }
        }
    }
    onResultEntriesChanged: Qt.callLater(root.reconcileSelection)
    Component.onCompleted: Qt.callLater(root.resetSelection)
}
