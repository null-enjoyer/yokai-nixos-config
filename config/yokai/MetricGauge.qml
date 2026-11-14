import QtQuick

Item {
    id: root
    property var percent: undefined
    property string caption: "Used"
    readonly property bool available: typeof percent === "number" && isFinite(percent)
    readonly property real fraction: available ? Math.max(0, Math.min(100, percent)) / 100 : 0
    readonly property color gaugeColor: available && percent >= 85 ? Theme.vermilion : Theme.ivory
    implicitWidth: 104
    implicitHeight: 104

    Canvas {
        id: ring
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const context = getContext("2d");
            context.reset();
            const radius = Math.min(width, height) / 2 - 5;
            const start = Math.PI * .75;
            const sweep = Math.PI * 1.5;
            context.lineWidth = 5;
            context.lineCap = "round";
            context.strokeStyle = Theme.border;
            context.beginPath();
            context.arc(width / 2, height / 2, radius, start, start + sweep);
            context.stroke();
            if (root.available && root.fraction > 0) {
                context.strokeStyle = root.gaugeColor;
                context.beginPath();
                context.arc(width / 2, height / 2, radius, start, start + sweep * root.fraction);
                context.stroke();
            }
        }
    }
    Column {
        anchors.centerIn: parent
        spacing: 2
        TextLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.available ? Math.round(root.percent) + "%" : "—"
            font.family: "JetBrains Mono"
            font.pixelSize: 21
            color: root.gaugeColor
        }
        TextLabel { anchors.horizontalCenter: parent.horizontalCenter; text: root.caption; font.pixelSize: 11; color: Theme.muted }
    }
    onFractionChanged: ring.requestPaint()
    onAvailableChanged: ring.requestPaint()
    onGaugeColorChanged: ring.requestPaint()
}
