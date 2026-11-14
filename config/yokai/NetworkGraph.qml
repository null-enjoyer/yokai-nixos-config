import QtQuick

Canvas {
    id: root
    property var samples: []
    property double windowStart: 0
    property double windowEnd: 0
    property string placeholder: "Collecting history…"
    readonly property real plotLeft: 72
    readonly property real plotRight: Math.max(plotLeft, width - 8)
    readonly property real plotTop: 12
    readonly property real plotBottom: Math.max(plotTop, height - 23)
    readonly property real peak: {
        const maximum = samples.reduce((highest, sample) => Math.max(highest,
            valid(sample.download) ? sample.download : 0, valid(sample.upload) ? sample.upload : 0), 1024);
        return Math.pow(2, Math.ceil(Math.log(maximum) / Math.LN2));
    }
    implicitHeight: 108
    function valid(value) { return typeof value === "number" && isFinite(value) && value >= 0; }
    function xPosition(time) { return plotLeft + (plotRight - plotLeft) * (time - windowStart) / Math.max(1, windowEnd - windowStart); }
    function yPosition(rate) { return plotBottom - (plotBottom - plotTop) * rate / peak; }
    function rateLabel(value) {
        if (value === 0) return "0";
        const units = ["B/s", "KiB/s", "MiB/s", "GiB/s"];
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
        return value.toFixed(value < 10 && value % 1 !== 0 ? 1 : 0) + " " + units[unit];
    }
    function timeLabel(time) { return Qt.formatDateTime(new Date(time * 1000), windowEnd - windowStart >= 86400 ? "MMM d, HH:mm" : "HH:mm"); }
    onSamplesChanged: requestPaint()
    onWindowStartChanged: requestPaint()
    onWindowEndChanged: requestPaint()
    onPlaceholderChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const context = getContext("2d");
        context.reset();
        context.font = '10px "JetBrains Mono"';
        context.lineWidth = 1;
        context.strokeStyle = "#7034343A";
        context.fillStyle = Theme.muted;
        context.textAlign = "right";
        for (let line = 0; line < 3; line++) {
            const rate = peak * (1 - line / 2);
            const y = yPosition(rate);
            context.beginPath(); context.moveTo(plotLeft, y); context.lineTo(plotRight, y); context.stroke();
            context.fillText(rateLabel(rate), plotLeft - 7, y + 3);
        }
        context.textAlign = "left";
        context.fillText(timeLabel(windowStart), plotLeft, height - 4);
        context.textAlign = "right";
        context.fillText(timeLabel(windowEnd), plotRight, height - 4);
        if (plotRight - plotLeft >= 320) {
            context.textAlign = "center";
            context.fillText(timeLabel((windowStart + windowEnd) / 2), (plotLeft + plotRight) / 2, height - 4);
        }
        let observed = false;
        function trace(field, color, filled) {
            let segment = [];
            function finish() {
                if (segment.length === 0) return;
                if (filled && segment.length > 1) {
                    context.beginPath(); context.moveTo(segment[0].x, plotBottom);
                    for (const point of segment) context.lineTo(point.x, point.y);
                    context.lineTo(segment[segment.length - 1].x, plotBottom);
                    context.closePath(); context.fillStyle = "#12F0EDE6"; context.fill();
                }
                context.beginPath(); context.moveTo(segment[0].x, segment[0].y);
                for (let index = 1; index < segment.length; index++) context.lineTo(segment[index].x, segment[index].y);
                context.lineWidth = filled ? 2.5 : 1.5; context.strokeStyle = color; context.stroke();
                if (segment.length === 1) {
                    context.beginPath(); context.arc(segment[0].x, segment[0].y, filled ? 2.5 : 1.5, 0, 2 * Math.PI);
                    context.fillStyle = color; context.fill();
                }
                segment = [];
            }
            for (const sample of samples) {
                // A directional gap marker must not interrupt the other series.
                if (sample.gap && sample.gap !== field) continue;
                if (!valid(sample.time) || sample.time < windowStart || sample.time > windowEnd || !valid(sample[field])) { finish(); continue; }
                observed = true;
                segment.push({x: xPosition(sample.time), y: yPosition(sample[field])});
            }
            finish();
        }
        trace("download", Theme.ivory, true);
        trace("upload", Theme.vermilion, false);
        if (!observed) {
            context.fillStyle = Theme.muted; context.textAlign = "center";
            context.fillText(placeholder, (plotLeft + plotRight) / 2, (plotTop + plotBottom) / 2 + 3);
        }
    }
}
