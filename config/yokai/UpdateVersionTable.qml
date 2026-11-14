pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    Layout.minimumWidth: 0
    Layout.preferredWidth: 0
    property var rows: []
    property string scope: "system"
    property bool flatpak: false
    property string emptyTitle: "No package updates"
    property string emptyDescription: ""
    readonly property real nameWidth: Math.max(100, (width - 20) * .44)
    readonly property real versionWidth: Math.max(1, (width - nameWidth - 32) / 2)
    property string rowSignature: ""

    function syncRows() {
        const signature = JSON.stringify(rows);
        if (signature === rowSignature) return;
        rowSignature = signature;
        for (let index = 0; index < rows.length; index++) {
            const row = rows[index];
            const entry = {
                packageName: String(row.name || row.id || "Unknown"),
                currentVersion: String(flatpak ? row.version || row.branch || "Unknown" : row.from || "Unknown"),
                availableVersion: String(flatpak ? "Update available" : row.to || "Unknown")
            };
            if (index < packages.count) packages.set(index, entry);
            else packages.append(entry);
        }
        if (packages.count > rows.length) packages.remove(rows.length, packages.count - rows.length);
    }
    onRowsChanged: Qt.callLater(syncRows)
    onFlatpakChanged: { rowSignature = ""; Qt.callLater(syncRows); }
    onScopeChanged: list.positionViewAtBeginning()
    Component.onCompleted: syncRows()
    ListModel { id: packages }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 10
            TextLabel { Layout.minimumWidth: 0; Layout.preferredWidth: root.nameWidth; text: "Package"; color: Theme.muted; font.pixelSize: 12 }
            TextLabel { Layout.minimumWidth: 0; Layout.preferredWidth: root.versionWidth; text: "Current"; color: Theme.muted; font.pixelSize: 12 }
            TextLabel { Layout.minimumWidth: 0; Layout.fillWidth: true; text: "Available"; color: Theme.muted; font.pixelSize: 12 }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ListView {
                id: list
                objectName: "update-version-list"
                anchors.fill: parent
                clip: true
                model: packages
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: entry
                    required property string packageName
                    required property string currentVersion
                    required property string availableVersion
                    width: list.width - 12
                    height: 32
                    RowLayout {
                        anchors.fill: parent
                        spacing: 10
                        TextLabel { Layout.minimumWidth: 0; Layout.preferredWidth: root.nameWidth; text: entry.packageName; font.pixelSize: 14 }
                        TextLabel { Layout.minimumWidth: 0; Layout.preferredWidth: root.versionWidth; text: entry.currentVersion; color: Theme.muted; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                        TextLabel { Layout.minimumWidth: 0; Layout.fillWidth: true; text: entry.availableVersion; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                    }
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: "#4034343A" }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 40)
                visible: packages.count === 0
                spacing: 10
                TextLabel { Layout.fillWidth: true; text: root.emptyTitle; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
                TextLabel { Layout.fillWidth: true; text: root.emptyDescription; color: Theme.muted; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
            }
        }
    }
}
