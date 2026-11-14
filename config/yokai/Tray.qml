pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Singleton {
    readonly property var items: SystemTray.items.values.filter(item => !["nm-applet", "blueman"].includes(item.id.toLowerCase()))
    function displayName(item) {
        return item.title || item.tooltipTitle || item.id.replace(/_status_icon_.*/, "");
    }
}
