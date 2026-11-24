import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    readonly property var sessionLock: LockScreen
    Binding {
        target: Updates
        property: "active"
        value: Desktop.panelMenu?.objectName === "yokai-updates" && Desktop.panelMenu.visible && !Desktop.panelMenu.closing
    }
    Binding {
        target: Weather
        property: "active"
        value: Desktop.panelMenu?.objectName === "yokai-hub" && Desktop.panelMenu.visible && !Desktop.panelMenu.closing
    }
    Variants { model: Theme.railScreens; delegate: Rail { required property var modelData; screen: modelData } }
    ControlPanel {}
    TelegramSetup {}
    BreakReminderPopup {}
    NotificationPopups {}
    Variants {
        model: Theme.development ? [] : Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "yokai-wallpaper"
            color: Theme.voidColor
            Wallpaper { anchors.fill: parent; directory: "file://" + (Quickshell.env("YOKAI_WALLPAPERS") || Quickshell.shellPath("../../wallpapers")) }
        }
    }
}
