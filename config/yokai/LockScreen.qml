pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Singleton {
    id: root
    readonly property bool locked: sessionState.locked || sessionState.secure
    readonly property bool secure: sessionState.locked && sessionState.secure
    readonly property bool waiting: pam.active && (!pam.responseRequired || state === "verifying")
    readonly property bool canSubmit: secure && !waiting && !retryDelay.running
    readonly property bool responseVisible: pam.responseRequired && pam.responseVisible
    readonly property string keyboardLayout: Compositor.keyboardLayoutShort
    property string input: ""
    property string prompt: "Password"
    property string feedback: ""
    property string state: "unlocked"

    QtObject {
        id: sessionState
        property bool locked: false
        property bool secure: false
    }

    function refreshSessionState() {
        // Native unlock notifications can precede cleanup of the lock object.
        sessionState.locked = session.locked;
        sessionState.secure = session.secure;
        if (root.secure) Qt.callLater(root.startAuthentication);
        else Qt.callLater(root.recoverFailedRequest);
    }
    Component.onCompleted: Qt.callLater(root.refreshSessionState)

    // Only the lock request survives a QML reload. Never retain credentials.
    PersistentProperties {
        id: retained
        reloadableId: "yokai-session-lock-state"
        property bool requested: false
        property bool watchedFiles: true
        onLoaded: {
            if (requested) {
                Quickshell.watchFiles = false;
                resumeAuthentication.start();
            }
        }
    }

    function lock() {
        if (retained.requested || session.locked) return;
        Desktop.close();
        Desktop.closePanelMenu();
        input = "";
        feedback = "";
        state = "locking";
        retained.watchedFiles = Quickshell.watchFiles;
        Quickshell.watchFiles = false;
        retained.requested = true;
        Qt.callLater(root.recoverFailedRequest);
    }

    function recoverFailedRequest() {
        // Denial notifications precede native cleanup. Run after that cleanup,
        // and never cancel a lock that is still waiting for acknowledgement.
        if (!retained.requested || session.locked) return;
        retained.requested = false;
        input = "";
        state = "error";
        feedback = "The compositor could not acquire the session lock. Try again.";
        Quickshell.watchFiles = retained.watchedFiles;
    }

    function startAuthentication() {
        if (!root.secure || pam.active) return;
        prompt = "Password";
        state = "starting";
        if (!pam.start()) {
            state = "error";
            feedback = "Authentication unavailable. Check the PAM service, then retry.";
        }
    }

    function submit() {
        if (!canSubmit) return;
        if (!pam.active) {
            input = "";
            feedback = "";
            startAuthentication();
            return;
        }
        if (!pam.responseRequired || input.length === 0) return;
        state = "verifying";
        feedback = "";
        pam.respond(input);
        input = "";
    }

    function edited(value) {
        input = value;
        if (pam.responseRequired) feedback = "";
    }

    WlSessionLock {
        id: session
        reloadableId: "yokai-session-lock"
        locked: retained.requested
        onSecureChanged: Qt.callLater(root.refreshSessionState)
        onLockedChanged: Qt.callLater(root.refreshSessionState)
        WlSessionLockSurface {
            color: Theme.voidColor
            LockContent { anchors.fill: parent; controller: root }
        }
    }

    PamContext {
        id: pam
        config: "yokai-lock"
        configDirectory: "/etc/pam.d"
        // PamContext resolves the current process uid itself, independent of $USER.
        onPamMessage: {
            if (responseRequired) {
                root.prompt = message.trim() || "Password";
                root.state = "prompt";
            } else if (messageIsError) {
                root.feedback = message;
            }
        }
        onCompleted: result => {
            root.input = "";
            if (!root.secure) return;
            if (result === PamResult.Success) {
                // This is the only path that releases a successfully acquired lock.
                retained.requested = false;
                root.state = "unlocked";
                root.feedback = "";
                Quickshell.watchFiles = retained.watchedFiles;
            } else if (result === PamResult.Failed) {
                root.state = "failed";
                root.feedback = "Incorrect password. Try again.";
                resumeAuthentication.restart();
            } else if (result === PamResult.MaxTries) {
                root.state = "cooldown";
                root.feedback = "Too many attempts. Wait a moment before trying again.";
                retryDelay.restart();
            } else {
                root.state = "error";
                root.feedback = "Authentication unavailable. Check the PAM service, then retry.";
            }
        }
    }

    Timer { id: resumeAuthentication; interval: 250; onTriggered: root.startAuthentication() }
    Timer { id: retryDelay; interval: 30000; onTriggered: root.startAuthentication() }

    IpcHandler {
        target: "yokai-lock"
        function lock(): void { root.lock(); }
        function status(): string {
            const nativeLocked = session.locked;
            const nativeSecure = session.secure;
            return JSON.stringify({ locked: nativeLocked || nativeSecure, secure: nativeLocked && nativeSecure,
                authenticating: pam.active, state: root.state });
        }
    }
}
