pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Wayland

AttachedPopup {
    id: root
    objectName: "yokai-updates"
    heading: "Updates"
    WlrLayershell.namespace: "yokai-updates"
    surfaceColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, .90)
    implicitWidth: Math.max(1, Math.min(960, (screen?.width ?? 1040) - anchor.rect.x - 24))
    implicitHeight: Math.max(1, Math.min(600, (screen?.height ?? 664) - 32))
    resizeFromBottom: false

    property string tab: "updates"
    property string scope: "system"
    property string historyScope: "activity"
    property string scheduleJobId: ""
    property bool viewingLog: false
    property bool viewingSources: false
    property int restoreGeneration: -1
    readonly property var systemRows: Updates.ready ? Updates.state.prepared?.packageChanges || [] : Updates.changes.system || []
    readonly property var toolRows: Updates.changes.tools || []
    readonly property var flatpakRows: Updates.changes.flatpak || []
    readonly property int totalChanges: systemRows.length + toolRows.length + flatpakRows.length
    readonly property int changedSources: [systemRows, toolRows, flatpakRows].filter(rows => rows.length > 0).length
    readonly property var selectedJob: Updates.automations.find(job => job.id === scheduleJobId) || Updates.automations[0] || null
    readonly property var sections: tab === "updates" ? [
        {id: "system", label: "System & apps", count: systemRows.length},
        {id: "tools", label: "CLI tools", count: toolRows.length},
        {id: "flatpak", label: "Flatpak", count: flatpakRows.length}
    ] : tab === "history" ? [
        {id: "activity", label: "Activity", count: Updates.history.length},
        {id: "generations", label: "System generations", count: Updates.generations.length}
    ] : Updates.automations.map(job => ({id: job.id, label: job.label, count: null}))
    readonly property string selectedSection: tab === "updates" ? scope : tab === "history" ? historyScope : selectedJob?.id || ""
    readonly property var packageRows: scope === "system" ? systemRows : scope === "tools" ? toolRows : flatpakRows
    readonly property bool flatpakSelected: tab === "updates" && scope === "flatpak"
    readonly property string primaryAction: flatpakSelected ? flatpakRows.length ? "flatpak" : "check"
        : Updates.ready ? "apply" : Updates.hasUpdates ? "prepare" : "check"
    readonly property string primaryLabel: ({flatpak: "Update Flatpak", apply: "Apply now", prepare: "Prepare update", check: "Check updates"})[primaryAction]
    readonly property string sectionTitle: viewingLog ? viewingSources ? "System source revisions" : "Operation log"
        : tab === "updates" ? ({system: "System & applications", tools: "CLI tools", flatpak: "Flatpak applications"})[scope]
        : tab === "history" ? historyScope === "generations" ? "System generations" : "Update history"
        : selectedJob?.label || "Automatic updates"
    readonly property string sectionDescription: viewingLog ? viewingSources ? "Source revisions are shown separately from package versions." : "Output from the selected operation."
        : tab === "updates" ? packageRows.length + (scope === "flatpak" ? " application updates" : scope === "tools" ? " tool updates" : " package updates")
        : tab === "history" ? historyScope === "generations" ? "Restore a previous system configuration and its packages." : "Manual operations and automatic updates."
        : "Runs automatically in the background."
    readonly property string checkError: Updates.state.checkErrors?.[scope] || ""
    readonly property string emptyTitle: !Updates.connected ? "Updates unavailable" : checkError ? "Check incomplete"
        : scope === "system" && Updates.hasUpdates && Updates.state.sourceChanges?.length ? "System sources changed"
        : !Updates.state.lastChecked ? "Not checked yet" : !Updates.state.lastCheckSuccessful ? "Check incomplete" : "No updates available"
    readonly property string emptyDescription: !Updates.connected ? "Waiting for the update service." : checkError ? checkError
        : scope === "system" && Updates.hasUpdates && Updates.state.sourceChanges?.length ? "Selected package versions are unchanged. A new system can still be prepared."
        : !Updates.state.lastChecked || !Updates.state.lastCheckSuccessful ? "Run a complete check to discover changes." : "This category is up to date."
    readonly property var lastSuccess: Updates.history.find(operation => operation.status === "success") || null
    readonly property string notice: !Updates.enabled ? "Updates are not enabled for this host."
        : !Updates.connected ? Updates.transportError || "Waiting for the update service."
        : Updates.error
    readonly property string restartNotice: Updates.state.restartRequired ? "Restart to use updated kernel or system components."
        : Updates.state.pendingBoot ? "The prepared system will be used on the next boot." : ""

    function systemVersionLabel(value) {
        const match = /^(\d{2}\.\d{2}(?:pre)?)(?:\.(\d{8}))?/.exec(String(value || ""));
        if (!match) return "Version unavailable";
        if (!match[2]) return match[1];
        const date = new Date(Number(match[2].slice(0, 4)), Number(match[2].slice(4, 6)) - 1, Number(match[2].slice(6, 8)));
        return match[1] + " · " + Qt.formatDate(date, "d MMM yyyy");
    }
    function selectSection(id) {
        viewingLog = false;
        restoreGeneration = -1;
        if (tab === "updates") scope = id;
        else if (tab === "history") historyScope = id;
        else scheduleJobId = id;
    }
    function openDetails(id) {
        viewingLog = true;
        viewingSources = false;
        Updates.showDetails(id);
    }
    function runPrimary() {
        if (!Updates.canAct) return;
        if (restoreGeneration < 1) { Updates.run(primaryAction); return; }
        Updates.run("rollback", restoreGeneration);
        restoreGeneration = -1;
    }
    onTabChanged: { viewingLog = false; restoreGeneration = -1; }
    onVisibleChanged: {
        Updates.detailsActive = visible && viewingLog && !viewingSources;
        if (!visible) restoreGeneration = -1;
    }
    onViewingLogChanged: Updates.detailsActive = visible && viewingLog && !viewingSources
    onViewingSourcesChanged: Updates.detailsActive = visible && viewingLog && !viewingSources
    Connections {
        target: Updates
        function onLatestIdChanged() { if (root.viewingLog && Updates.running) Updates.showDetails(Updates.latestId); }
    }

    popupContents: [
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            anchors.leftMargin: 38
            spacing: 14
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    TextLabel { text: "Updates"; font.pixelSize: 24; font.weight: Font.DemiBold }
                    TextLabel {
                        Layout.fillWidth: true
                        text: Updates.state.lastChecked ? (Updates.state.lastCheckSuccessful ? "Checked · " : "Check incomplete · ") + Updates.formatTime(Updates.state.lastChecked) : "Not checked yet"
                        color: Theme.muted; font.pixelSize: 12
                    }
                    UpdateButton {
                        objectName: "updates-refresh"
                        implicitWidth: 36; implicitHeight: 36
                        leftPadding: 9; rightPadding: 9
                        iconName: "view-refresh-symbolic"
                        Accessible.name: "Check updates"
                        enabled: Updates.enabled && !Updates.running
                        onClicked: Updates.connected ? Updates.run("check") : Updates.refresh()
                    }
                    CloseButton { implicitWidth: 36; implicitHeight: 36; onClicked: root.closeReveal() }
                }
                RowLayout {
                    spacing: 8
                    Repeater {
                        model: [
                            {id: "updates", label: "Updates", icon: "folder-download-symbolic"},
                            {id: "history", label: "History", icon: "document-open-recent-symbolic"},
                            {id: "schedule", label: "Schedule", icon: "x-office-calendar-symbolic"}
                        ]
                        UpdateButton {
                            required property var modelData
                            objectName: "updates-tab-" + modelData.id
                            implicitWidth: 126
                            text: modelData.label
                            iconName: modelData.icon
                            tab: true
                            selected: root.tab === modelData.id
                            onClicked: root.tab = modelData.id
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                spacing: 20
                ColumnLayout {
                    Layout.preferredWidth: root.width < 820 ? 164 : 204
                    Layout.minimumWidth: Layout.preferredWidth
                    Layout.maximumWidth: Layout.preferredWidth
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    spacing: 10
                    Flickable {
                        id: sidebarViewport
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 0
                        contentWidth: width
                        contentHeight: sidebar.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ColumnLayout {
                            id: sidebar
                            width: sidebarViewport.width
                            spacing: 10
                            Repeater {
                                model: root.sections
                                UpdateButton {
                                    required property var modelData
                                    objectName: "updates-section-" + modelData.id
                                    Layout.fillWidth: true
                                    implicitHeight: 42
                                    text: modelData.label
                                    trailingText: modelData.count === null ? "" : String(modelData.count)
                                    selected: root.selectedSection === modelData.id
                                    onClicked: root.selectSection(modelData.id)
                                }
                            }
                            Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; implicitHeight: 1; color: Theme.border }
                            TextLabel {
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                text: "NixOS " + root.systemVersionLabel(Updates.state.systemVersion?.from)
                                color: Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap
                            }
                            TextLabel {
                                Layout.fillWidth: true
                                visible: Boolean(Updates.state.systemVersion?.to) && Updates.state.systemVersion?.to !== Updates.state.systemVersion?.from
                                text: "Available · " + root.systemVersionLabel(Updates.state.systemVersion?.to)
                                color: Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap
                            }
                            TextLabel { Layout.fillWidth: true; text: Updates.title; color: Updates.failed ? Theme.vermilion : Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap }
                        }
                    }
                    UpdateButton {
                        Layout.fillWidth: true
                        text: "Operation log"; iconName: "view-list-symbolic"
                        enabled: Boolean(Updates.latestId)
                        selected: root.viewingLog
                        onClicked: root.viewingLog ? root.viewingLog = false : root.openDetails(Updates.latestId)
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Theme.border }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    Layout.minimumHeight: 0
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        TextLabel { Layout.fillWidth: true; text: root.sectionTitle; font.pixelSize: 21; font.weight: Font.DemiBold }
                        UpdateButton { visible: root.viewingLog; text: "Back"; iconName: "go-previous-symbolic"; onClicked: root.viewingLog = false }
                    }
                    TextLabel { Layout.fillWidth: true; text: root.sectionDescription; color: Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap }
                    UpdateVersionTable {
                        id: versionTable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.viewingLog && root.tab === "updates"
                        rows: root.packageRows
                        scope: root.scope
                        flatpak: root.scope === "flatpak"
                        emptyTitle: root.emptyTitle
                        emptyDescription: root.emptyDescription
                    }
                    UpdateHistory {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.viewingLog && root.tab === "history"
                        generations: root.historyScope === "generations"
                        onShowLog: operationId => root.openDetails(operationId)
                        onRestore: generation => root.restoreGeneration = generation
                    }
                    UpdateSchedule {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: !root.viewingLog && root.tab === "schedule"
                        job: root.selectedJob
                        onShowLog: operationId => root.openDetails(operationId)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.viewingLog
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            UpdateButton { text: "Log"; selected: !root.viewingSources; onClicked: root.viewingSources = false }
                            UpdateButton { text: "Sources"; trailingText: String(Updates.state.sourceChanges?.length || 0); selected: root.viewingSources; onClicked: root.viewingSources = true }
                            Item { Layout.fillWidth: true }
                            UpdateButton { text: "Latest"; enabled: Boolean(Updates.latestId); onClicked: { root.viewingSources = false; Updates.showDetails(Updates.latestId); } }
                        }
                        UpdateVersionTable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: root.viewingSources
                            scope: "sources"
                            rows: Updates.state.sourceChanges || []
                            emptyTitle: "No source revisions"
                            emptyDescription: "Source changes will appear after a check."
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !root.viewingSources
                            radius: 4; color: Theme.voidColor; border.color: Theme.border
                            Flickable {
                                id: logViewport
                                anchors.fill: parent; anchors.margins: 12
                                clip: true
                                contentWidth: width; contentHeight: logText.implicitHeight
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                TextEdit {
                                    id: logText
                                    width: logViewport.width
                                    readOnly: true; selectByMouse: true; textFormat: TextEdit.PlainText
                                    wrapMode: TextEdit.WrapAnywhere
                                    color: Theme.muted; font.family: "JetBrains Mono"; font.pixelSize: 11
                                    text: Updates.detailError || Updates.detailLog || (Updates.loadingDetails ? "Loading log…" : Updates.detailId ? "No log output yet." : "No operation selected.")
                                }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.notice !== ""
                TextLabel {
                    Layout.fillWidth: true
                    text: root.notice
                    color: Updates.failed ? Theme.vermilion : Theme.muted
                    font.pixelSize: 12; wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2; elide: Text.ElideRight
                }
                UpdateButton { visible: Updates.failed; text: "Copy error"; enabled: Boolean(Updates.error || Updates.detailError || Updates.detailLog); onClicked: Updates.copyError() }
            }
            TextLabel {
                Layout.fillWidth: true
                visible: root.restartNotice !== ""
                text: root.restartNotice
                color: Theme.muted; font.pixelSize: 12; wrapMode: Text.Wrap
            }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 2
                visible: Updates.running
                color: Theme.border
                Rectangle {
                    anchors.fill: parent; color: Theme.vermilion
                    SequentialAnimation on opacity {
                        running: Updates.running; loops: Animation.Infinite
                        NumberAnimation { to: .25; duration: 900 }
                        NumberAnimation { to: 1; duration: 900 }
                    }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    TextLabel {
                        Layout.fillWidth: true
                        text: root.restoreGeneration >= 1 ? "Restore generation " + root.restoreGeneration + "?"
                            : Updates.running ? Updates.stageLabel : root.totalChanges > 0 ? root.totalChanges + " updates across " + root.changedSources + " sources" : Updates.title
                        font.pixelSize: 13; font.weight: Font.DemiBold
                    }
                    TextLabel {
                        Layout.fillWidth: true
                        text: root.restoreGeneration >= 1 ? "Restore system packages and configuration. Flatpak is unaffected."
                            : Updates.running ? Updates.elapsed : root.tab === "updates" && root.scope === "flatpak" ? "Flatpak updates run separately."
                            : root.lastSuccess ? "Last successful operation · " + Updates.formatTime(root.lastSuccess.finishedAt || root.lastSuccess.startedAt) : "No successful operations recorded."
                        color: Theme.muted; font.pixelSize: 11
                    }
                }
                UpdateButton { visible: root.restoreGeneration >= 1; text: "Cancel"; onClicked: root.restoreGeneration = -1 }
                UpdateButton { visible: root.restoreGeneration < 1 && Updates.state.status === "failed"; text: "Retry"; enabled: Updates.canAct; onClicked: Updates.run("retry") }
                UpdateButton { visible: root.restoreGeneration < 1 && Updates.ready && !root.flatpakSelected; text: "On next boot"; enabled: Updates.canAct; onClicked: Updates.run("boot") }
                UpdateButton {
                    objectName: "updates-primary-action"
                    implicitWidth: root.restoreGeneration >= 1 ? 156 : 176
                    text: root.restoreGeneration >= 1 ? "Confirm restore" : Updates.running ? "Working…" : root.primaryLabel
                    iconName: root.restoreGeneration >= 1 ? "edit-undo-symbolic" : root.primaryAction === "check" ? "view-refresh-symbolic" : "folder-download-symbolic"
                    highlighted: true
                    enabled: Updates.canAct
                    onClicked: root.runPrimary()
                }
            }
        }
    ]
    contentItem.Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) { root.closeReveal(); event.accepted = true; }
    }
}
