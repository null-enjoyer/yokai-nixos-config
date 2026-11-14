pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root
    property var popups: []
    property var seen: []
    property bool quiet: false
    readonly property var notifications: server.trackedNotifications.values.filter(note => !note.transient).slice().sort((a, b) => b.id - a.id)
    readonly property int unread: notifications.filter(note => !seen.includes(note.id)).length
    function markRead() { seen = notifications.map(note => note.id); }
    function removePopup(id) { popups = popups.filter(popup => popup.id !== id); }
    function hidePopup(note) { removePopup(note.id); if (note.transient) note.expire(); }
    function dismiss(note) { removePopup(note.id); note.dismiss(); }
    function clear() { for (const note of notifications.slice()) dismiss(note); seen = []; }
    function activate(note) {
        const action = note.actions.find(action => action.identifier === "default");
        if (action) action.invoke();
        else hidePopup(note);
    }
    function received(note) {
        if (note.transient && (note.lastGeneration || quiet)) return;
        note.tracked = true;
        if (note.lastGeneration) return;
        removePopup(note.id);
        seen = seen.filter(id => id !== note.id);
        if (!quiet) {
            // Critical alerts stay visible until dismissed. Other popups are
            // temporary even when their sender requests no timeout.
            const expires = note.urgency === NotificationUrgency.Critical ? 0 : Date.now() + 6000;
            while (popups.length >= 3) {
                const removable = popups.find(popup => popup.expires > 0);
                if (!removable) break;
                const oldest = server.trackedNotifications.values.find(item => item.id === removable.id);
                if (oldest) hidePopup(oldest); else removePopup(removable.id);
            }
            popups = [...popups, {id: note.id, output: Desktop.focusedScreen()?.name ?? "", expires: expires}];
        }
    }
    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        onNotification: note => root.received(note)
    }
    Variants {
        model: server.trackedNotifications.values
        Connections {
            required property var modelData
            target: modelData
            function onClosed() { root.removePopup(modelData.id); }
        }
    }
    Timer {
        interval: 250; repeat: true; running: root.popups.length > 0
        onTriggered: {
            const expired = root.popups.filter(popup => popup.expires > 0 && popup.expires <= Date.now());
            for (const popup of expired) {
                const note = server.trackedNotifications.values.find(note => note.id === popup.id);
                if (note) root.hidePopup(note); else root.removePopup(popup.id);
            }
        }
    }
    Timer {
        interval: 5000; repeat: true; running: root.notifications.length > 100
        onTriggered: { for (const note of root.notifications.slice(100)) root.dismiss(note); }
    }
    function popupNotifications(output) {
        return popups.filter(popup => popup.output === output).map(popup => server.trackedNotifications.values.find(note => note.id === popup.id)).filter(note => note !== undefined);
    }
}
