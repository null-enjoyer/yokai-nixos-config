import QtQuick
import Quickshell

ShellRoot {
    // Safe visual preview: a regular window, without session lock or PAM.
    QtObject {
        id: preview
        property string input: ""
        property string prompt: "Password"
        property string feedback: ""
        readonly property string state: "preview"
        readonly property bool canSubmit: true
        readonly property bool waiting: false
        readonly property bool responseVisible: false
        readonly property string keyboardLayout: "EN"
        function edited(value) { input = value; feedback = ""; }
        function submit() { input = ""; feedback = "Preview only — authentication is disabled."; }
    }
    FloatingWindow {
        title: "YŌKAI lock screen preview"
        implicitWidth: 1280
        implicitHeight: 850
        color: Theme.voidColor
        LockContent { id: content; anchors.fill: parent; controller: preview }
        Timer {
            interval: 750
            running: Boolean(Quickshell.env("YOKAI_LOCK_PREVIEW_IMAGE"))
            onTriggered: content.grabToImage(result => result.saveToFile(Quickshell.env("YOKAI_LOCK_PREVIEW_IMAGE")))
        }
    }
}
