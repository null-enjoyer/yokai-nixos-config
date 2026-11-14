pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property bool generations: false
    signal showLog(string operationId)
    signal restore(int generation)
    property var rows: []
    property string rowSignature: ""

    function syncRows() {
        const values = generations ? Updates.generations : Updates.history;
        const signature = JSON.stringify(values);
        if (signature === rowSignature) return;
        rowSignature = signature;
        rows = values;
    }
    onGenerationsChanged: { rowSignature = ""; syncRows(); list.positionViewAtBeginning(); }
    Component.onCompleted: syncRows()
    Connections { target: Updates; function onStateChanged() { root.syncRows(); } }
    ListView {
        id: list
        objectName: "updates-history-list"
        anchors.fill: parent
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        spacing: 0
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: entry
            required property var modelData
            width: list.width - 12
            height: 76
            RowLayout {
                anchors.fill: parent
                anchors.rightMargin: 2
                spacing: 14
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    TextLabel {
                        Layout.fillWidth: true
                        text: root.generations ? "Generation " + entry.modelData.number
                            + (entry.modelData.current ? " · current" : entry.modelData.booted ? " · booted" : "")
                            : entry.modelData.action + " · " + entry.modelData.status
                        color: !root.generations && entry.modelData.status === "failed" ? Theme.vermilion : Theme.ivory
                    }
                    TextLabel {
                        Layout.fillWidth: true
                        text: Updates.formatTime(root.generations ? entry.modelData.date : entry.modelData.finishedAt || entry.modelData.startedAt)
                        color: Theme.muted; font.pixelSize: 12
                    }
                }
                UpdateButton {
                    text: root.generations ? "Restore" : "Log"
                    visible: !root.generations || !entry.modelData.current
                    enabled: !root.generations || Updates.canAct
                    onClicked: root.generations ? root.restore(entry.modelData.number) : root.showLog(entry.modelData.id)
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.border }
        }
    }
    TextLabel {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - 40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        visible: root.rows.length === 0
        color: Theme.muted
        text: root.generations ? "No system generations available." : "No recorded operations."
    }
}
