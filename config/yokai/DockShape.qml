import QtQuick

Canvas {
    id: root
    property bool connected: true
    property color fillColor: Theme.surface
    property color strokeColor: Theme.border
    property real neckTop: 12
    property real neckHeight: 22
    property real columnWidth: 0
    property real sideTop: 0
    property real sideHeight: 0
    readonly property real inset: 14
    onConnectedChanged: requestPaint()
    onFillColorChanged: requestPaint()
    onStrokeColorChanged: requestPaint()
    onNeckTopChanged: requestPaint()
    onNeckHeightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColumnWidthChanged: requestPaint()
    onSideTopChanged: requestPaint()
    onSideHeightChanged: requestPaint()
    function contour(ctx, fill) {
        const s = .5, w = width - s, h = height - s, x = inset;
        const top = Math.max(0, Math.min(height - neckHeight, neckTop));
        const bottom = Math.min(h, top + neckHeight);
        const r = 6;
        ctx.beginPath();
        ctx.moveTo(x + r, s);
        const step = Math.max(s, Math.min(h - r, sideTop));
        if (columnWidth > x + 2 * r && columnWidth < w - r && step > 2 * r && sideHeight > 0) {
            // The tray strip stays tall while a short application's menu
            // occupies only the lower part of the surface beside it.
            ctx.lineTo(columnWidth - r, s);
            ctx.quadraticCurveTo(columnWidth, s, columnWidth, r);
            ctx.lineTo(columnWidth, step - r);
            ctx.quadraticCurveTo(columnWidth, step, columnWidth + r, step);
            ctx.lineTo(w - r, step);
            ctx.quadraticCurveTo(w, step, w, step + r);
        } else {
            ctx.lineTo(w - r, s); ctx.quadraticCurveTo(w, s, w, r);
        }
        ctx.lineTo(w, h - r); ctx.quadraticCurveTo(w, h, w - r, h);
        ctx.lineTo(x + r, h); ctx.quadraticCurveTo(x, h, x, h - r);
        if (connected && neckHeight > 0) {
            ctx.lineTo(x, bottom); ctx.lineTo(0, bottom);
            if (fill) ctx.lineTo(0, top);
            else ctx.moveTo(0, top); // the connector stays open toward the panel
            ctx.lineTo(x, top);
        }
        ctx.lineTo(x, r); ctx.quadraticCurveTo(x, s, x + r, s);
        if (fill) ctx.closePath();
    }
    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        if (width < 24 || height < 24) return;
        contour(ctx, true); ctx.fillStyle = fillColor; ctx.fill();
        contour(ctx, false); ctx.strokeStyle = strokeColor; ctx.lineWidth = 1; ctx.stroke();
    }
}
