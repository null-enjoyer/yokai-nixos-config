pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "Fuzzy.js" as Fuzzy

ColumnLayout {
    id: root
    signal cycleMode(int direction)
    property string selectedId: ""
    readonly property var rows: {
        const queries = Fuzzy.keyboardQueries(Desktop.query);
        return Clipboard.entries.map((entry, index) => ({entry: entry, index: index,
            score: Math.max(...queries.map(query => Fuzzy.score(query, entry.text || entry.title)))}))
            .filter(row => row.score >= 0)
            .sort((left, right) => right.score - left.score || left.index - right.index)
            .map(row => row.entry);
    }
    readonly property var selected: rows.find(entry => entry.id === selectedId) ?? null
    spacing: 12
    function focusSearch() { search.forceActiveFocus(); }
    function select(index) {
        const entry = rows[index];
        selectedId = entry?.id ?? "";
        history.currentIndex = entry ? index : -1;
        if (entry) history.positionViewAtIndex(index, ListView.Contain);
    }
    function move(direction) {
        select(Math.max(0, Math.min(rows.length - 1, rows.findIndex(entry => entry.id === selectedId) + direction)));
    }
    onRowsChanged: {
        const index = rows.findIndex(entry => entry.id === selectedId);
        select(index < 0 && rows.length ? 0 : index);
    }
    TextField {
        id: search
        Layout.fillWidth: true
        Layout.preferredHeight: 46
        leftPadding: 14; rightPadding: 14
        font.family: "Inter"; font.pixelSize: 15
        color: Theme.ivory; placeholderTextColor: Theme.muted
        selectionColor: Theme.selection; selectedTextColor: Theme.ivory
        text: Desktop.query
        placeholderText: "Search clipboard…"
        selectByMouse: true
        background: Rectangle { radius: 10; color: "#20000000"; border.color: search.activeFocus ? "#A6D92B3A" : "#20FFFFFF" }
        onTextChanged: {
            if (Desktop.mode !== "clipboard") return;
            Desktop.query = text;
            root.select(root.rows.length ? 0 : -1);
        }
        onAccepted: if (root.selected) Clipboard.copy(root.selected.id, true)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.cycleMode(event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? -1 : 1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                root.move(event.key === Qt.Key_Down ? 1 : -1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete && event.modifiers & Qt.ControlModifier && root.selected) {
                Clipboard.change("delete", root.selected.id);
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                Desktop.close(); event.accepted = true;
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        TextLabel {
            Layout.fillWidth: true
            text: Clipboard.paused ? "History paused" : root.rows.length + " items"
            color: Clipboard.paused ? Theme.ivory : Theme.muted
            font.pixelSize: 12
        }
        YokaiButton {
            text: Clipboard.paused ? "Resume" : "Pause"
            enabled: Clipboard.ready && !Clipboard.busy
            onClicked: Clipboard.change("pause")
        }
        YokaiButton {
            text: "Clear"
            enabled: Clipboard.ready && !Clipboard.busy && Clipboard.entries.some(entry => !entry.pinned)
            onClicked: Clipboard.change("clear")
        }
    }
    Item {
        Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 0
        ListView {
            id: history
            anchors.fill: parent
            model: root.rows
            spacing: 6; clip: true
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: root.selectedId === modelData.id
                width: history.width
                height: modelData.kind === "image" ? 112 : 78
                radius: 9
                color: selected ? "#24FFFFFF" : pointer.containsMouse ? "#10FFFFFF" : "transparent"
                Rectangle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 26; radius: 1.5; color: Theme.vermilion; visible: row.selected }
                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.select(row.index); search.forceActiveFocus(); }
                    onDoubleClicked: Clipboard.copy(row.modelData.id, true)
                }
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                    Image {
                        visible: row.modelData.kind === "image"
                        Layout.preferredWidth: 110; Layout.fillHeight: true
                        source: row.modelData.thumbnail
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 220; sourceSize.height: 176
                        asynchronous: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 5
                        TextLabel {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            font.pixelSize: 14
                            font.weight: row.selected ? Font.DemiBold : Font.Normal
                        }
                        TextLabel {
                            Layout.fillWidth: true
                            text: row.modelData.kind === "image" ? Math.ceil(row.modelData.size / 1024) + " KiB"
                                : row.modelData.text.replace(/\s+/g, " ")
                            color: Theme.muted; font.pixelSize: 12
                            wrapMode: Text.WordWrap; maximumLineCount: 2
                        }
                    }
                    IconImage {
                        visible: row.modelData.pinned
                        implicitSize: 16
                        source: Quickshell.iconPath("view-pin-symbolic", "starred-symbolic")
                    }
                }
            }
            ScrollBar.vertical: ScrollBar { width: 3; policy: ScrollBar.AsNeeded }
        }
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 24
            visible: root.rows.length === 0
            spacing: 8
            TextLabel {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: !Clipboard.ready ? "Loading clipboard…" : Desktop.query ? "No matches" : "Clipboard is empty"
                font.pixelSize: 15
            }
            TextLabel {
                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                text: Clipboard.paused ? "Resume history to collect copied items" : "Copy text or an image to keep it here"
                color: Theme.muted; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }
    TextLabel {
        visible: Clipboard.error !== ""
        Layout.fillWidth: true
        text: Clipboard.error; color: Theme.vermilion
        wrapMode: Text.WordWrap; font.pixelSize: 12
    }
    RowLayout {
        Layout.fillWidth: true
        YokaiButton {
            text: root.selected?.pinned ? "Unpin" : "Pin"
            enabled: root.selected !== null && !Clipboard.busy
            onClicked: Clipboard.change("pin", root.selected.id)
        }
        YokaiButton {
            text: "Delete"
            enabled: root.selected !== null && !Clipboard.busy
            onClicked: Clipboard.change("delete", root.selected.id)
        }
        Item { Layout.fillWidth: true }
        YokaiButton {
            text: "Copy"
            enabled: root.selected !== null && !Clipboard.busy
            onClicked: Clipboard.copy(root.selected.id)
        }
        YokaiButton {
            text: "Paste"
            highlighted: true
            enabled: root.selected !== null && !Clipboard.busy && Desktop.clipboardTarget !== null
            onClicked: Clipboard.copy(root.selected.id, true)
        }
    }
}
