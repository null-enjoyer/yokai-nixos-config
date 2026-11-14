pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: root
    property var job: null
    signal showLog(string operationId)
    contentWidth: width
    contentHeight: body.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    ColumnLayout {
        id: body
        width: Math.max(0, root.width - 12)
        spacing: 22
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            TextLabel { text: "Next run"; color: Theme.muted; font.pixelSize: 12 }
            TextLabel { Layout.fillWidth: true; text: root.job ? Updates.formatTime(root.job.nextRun) : "Schedule unavailable"; font.pixelSize: 20; wrapMode: Text.Wrap }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.border }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            TextLabel { text: "Last run"; color: Theme.muted; font.pixelSize: 12 }
            TextLabel { Layout.fillWidth: true; text: root.job?.lastRun ? Updates.formatTime(root.job.lastRun) : "No recorded run"; wrapMode: Text.Wrap }
            TextLabel {
                Layout.fillWidth: true
                text: root.job?.result || root.job?.state || "Not available"
                color: root.job?.result === "failed" || root.job?.error ? Theme.vermilion : Theme.muted
                font.pixelSize: 13
            }
        }
        TextLabel { Layout.fillWidth: true; visible: Boolean(root.job?.error); text: root.job?.error || ""; color: Theme.vermilion; font.pixelSize: 13; wrapMode: Text.WrapAnywhere }
        RowLayout {
            Layout.fillWidth: true
            UpdateButton {
                visible: Boolean(root.job)
                text: "View log"; iconName: "view-list-symbolic"
                onClicked: root.showLog("automation:" + root.job.id)
            }
            UpdateButton {
                visible: root.job?.state === "failed" || Boolean(root.job?.error)
                text: root.job?.id.indexOf("flatpak") >= 0 ? "Retry" : "Prepare update"
                highlighted: true
                enabled: Updates.canAct
                onClicked: Updates.run(root.job.id.indexOf("flatpak") >= 0 ? "flatpak" : "prepare")
            }
            Item { Layout.fillWidth: true }
        }
    }
}
