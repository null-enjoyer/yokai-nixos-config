pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property color voidColor: "#09090B"
    readonly property color surface: "#141417"
    readonly property color elevated: "#202024"
    readonly property color border: "#34343A"
    readonly property color ivory: "#F0EDE6"
    readonly property color white: "#FFFFFF"
    readonly property color muted: "#929098"
    readonly property color vermilion: "#D92B3A"
    readonly property color neon: "#FF354F"
    readonly property color selection: "#681723"
    readonly property int railWidth: Number(Quickshell.env("YOKAI_RAIL_WIDTH") || 48)
    readonly property real railIconSize: 20.5
    readonly property var railExcludedOutputs: JSON.parse(Quickshell.env("YOKAI_RAIL_EXCLUDED_OUTPUTS") || "[]")
    readonly property var railScreens: Quickshell.screens.filter(screen => {
        const monitor = Compositor.monitors.find(item => item.name === screen.name);
        return !railExcludedOutputs.includes(screen.name)
            && !railExcludedOutputs.includes("desc:" + (monitor?.description ?? ""));
    })
    readonly property bool development: Quickshell.env("YOKAI_DEVELOPMENT") === "1"
    readonly property bool showActiveEmpty: Quickshell.env("YOKAI_SHOW_ACTIVE_EMPTY") !== "0"
    readonly property var folderRoots: Quickshell.env("YOKAI_FOLDER_ROOTS") ? JSON.parse(Quickshell.env("YOKAI_FOLDER_ROOTS")) : [Quickshell.env("HOME")]
}
