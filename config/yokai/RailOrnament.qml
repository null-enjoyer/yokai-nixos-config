import QtQuick

Item {
    id: root
    property bool flowStartPending: true
    property color ink: Theme.ivory
    property real strength: 0.14
    readonly property var flames: [
        {top: 0.008, position: 0.18, length: 48, span: 20, angle: 4, curl: 0.84},
        {top: 0.036, position: 0.84, length: 45, span: 16, angle: 6, curl: 0.82},
        {top: 0.062, position: 0.49, length: 56, span: 20, angle: 7, curl: 0.77},
        {top: 0.111, position: 0.04, length: 40, span: 14, angle: -3, curl: 0.89},
        {top: 0.134, position: 0.67, length: 63, span: 22, angle: 8, curl: 0.73},
        {top: 0.169, position: 0.32, length: 42, span: 16, angle: -4, curl: 0.91},
        {top: 0.203, position: 0.92, length: 51, span: 18, angle: 6, curl: 0.86},
        {top: 0.241, position: 0.11, length: 53, span: 18, angle: 5, curl: 0.86},
        {top: 0.296, position: 0.54, length: 56, span: 18, angle: 8, curl: 0.77},
        {top: 0.332, position: 0.78, length: 47, span: 14, angle: -5, curl: 0.70},
        {top: 0.355, position: 0.27, length: 68, span: 22, angle: 9, curl: 0.86},
        {top: 0.411, position: 0.97, length: 44, span: 20, angle: 5, curl: 0.80},
        {top: 0.438, position: 0.42, length: 40, span: 18, angle: 7, curl: 0.92},
        {top: 0.487, position: 0.06, length: 42, span: 14, angle: 4, curl: 0.91},
        {top: 0.525, position: 0.71, length: 59, span: 20, angle: 8, curl: 0.75},
        {top: 0.549, position: 0.22, length: 51, span: 22, angle: 5, curl: 0.88},
        {top: 0.606, position: 0.58, length: 46, span: 16, angle: 4, curl: 0.81},
        {top: 0.635, position: 0.89, length: 61, span: 18, angle: 7, curl: 0.79},
        {top: 0.671, position: 0.35, length: 44, span: 16, angle: -3, curl: 0.83},
        {top: 0.713, position: 0.02, length: 66, span: 20, angle: 9, curl: 0.74},
        {top: 0.737, position: 0.64, length: 52, span: 20, angle: 4, curl: 0.87},
        {top: 0.789, position: 0.14, length: 58, span: 20, angle: 7, curl: 0.77},
        {top: 0.834, position: 0.82, length: 49, span: 18, angle: 6, curl: 0.82},
        {top: 0.853, position: 0.47, length: 62, span: 22, angle: 8, curl: 0.78},
        {top: 0.909, position: 0.95, length: 41, span: 14, angle: -2, curl: 0.90},
        {top: 0.947, position: 0.29, length: 50, span: 18, angle: 7, curl: 0.85},
        {top: 0.982, position: 0.73, length: 56, span: 18, angle: 5, curl: 0.84}
    ]
    function restartFlow() {
        if (LockScreen.locked || !root.visible || root.height <= 0 || root.width <= 0) return;
        horizontalMotion.restart();
        verticalMotion.restart();
        root.flowStartPending = false;
    }
    Component.onCompleted: Qt.callLater(restartFlow)
    onWidthChanged: {
        flowStartPending = true;
        Qt.callLater(restartFlow);
    }
    onHeightChanged: {
        flowStartPending = true;
        Qt.callLater(restartFlow);
    }
    clip: true
    enabled: false

    function flame(ctx, mark, periodX, periodY) {
        const span = mark.span, length = mark.length;
        const outerStart = {x: span * 0.02, y: length * 0.48};
        const outerEnd = {x: span * mark.curl, y: length * 0.30};
        const tip = {x: span * 0.96, y: length};
        const innerEnd = {x: span * 0.58, y: length * 0.64};
        const innerStart = {x: span * 0.08, y: length * 0.62};
        const angle = mark.angle * Math.PI / 180;
        const cosine = Math.cos(angle), sine = Math.sin(angle);
        let minX = 0, maxX = 0;
        // Keep the entire curve's control hull inside the rail, including both tips.
        for (const point of [outerStart, outerEnd, tip, innerEnd, innerStart]) {
            const x = point.x * cosine - point.y * sine;
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
        }
        const padding = 2;
        const available = Math.max(0, width - padding * 2 - (maxX - minX));
        const origin = padding - minX + available * mark.position;
        ctx.save();
        ctx.translate(origin + periodX, height * mark.top + periodY);
        ctx.rotate(angle);
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.bezierCurveTo(outerStart.x, outerStart.y, outerEnd.x, outerEnd.y, tip.x, tip.y);
        ctx.bezierCurveTo(innerEnd.x, innerEnd.y, innerStart.x, innerStart.y, 0, 0);
        ctx.closePath();
        ctx.globalAlpha = root.strength;
        ctx.fill();
        ctx.restore();
    }

    Canvas {
        id: strip
        width: root.width * 2
        height: root.height * 2
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (root.width <= 0 || root.height <= 0) return;
            ctx.fillStyle = root.ink;
            ctx.globalAlpha = 1;
            // Include the previous period so curls crossing the seam retain both tips.
            for (const y of [-root.height, 0, root.height]) {
                for (const x of [-root.width, 0, root.width]) {
                    for (const mark of root.flames) root.flame(ctx, mark, x, y);
                }
            }
            ctx.globalAlpha = 1;
        }
    }
    Connections {
        target: root
        function onInkChanged() { strip.requestPaint(); }
        function onStrengthChanged() { strip.requestPaint(); }
    }
    Connections {
        target: LockScreen
        function onLockedChanged() {
            if (!LockScreen.locked && root.flowStartPending) Qt.callLater(root.restartFlow);
        }
    }
    NumberAnimation {
        id: horizontalMotion
        target: strip
        property: "x"
        from: 0
        to: -root.width
        duration: 20000
        loops: Animation.Infinite
        easing.type: Easing.Linear
        running: root.visible && root.width > 0
        paused: LockScreen.locked
    }
    NumberAnimation {
        id: verticalMotion
        target: strip
        property: "y"
        from: 0
        to: -root.height
        duration: 300000
        loops: Animation.Infinite
        easing.type: Easing.Linear
        running: root.visible && root.height > 0
        paused: LockScreen.locked
    }
}
