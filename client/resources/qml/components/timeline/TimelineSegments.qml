import QtQuick 2.15

Item {
    id: segments

    property var recordings: []
    property var timeline: null
    property real viewStart: 0
    property real viewEnd: 0
    property real contentWidth: 1

    function mapX(tsMs) {
        var s = viewStart
        var e = viewEnd
        var w = Math.max(1, contentWidth)
        if (e <= s)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    // Keep hundreds/thousands of recording blocks in one paint operation
    // instead of creating one QML item and bindings per recording.
    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: false

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var h = Math.max(8, segments.height * 0.35)
            var y = segments.height - h - 2
            ctx.fillStyle = "#2E7D32"
            ctx.globalAlpha = 0.85

            for (var i = 0; i < segments.recordings.length; ++i) {
                var rec = segments.recordings[i]
                var x1 = segments.mapX(Number(rec.start) * 1000)
                var x2 = segments.mapX(Number(rec.end) * 1000)
                var w = Math.max(2, x2 - x1)
                ctx.fillRect(x1, y, w, h)
            }
        }
    }

    onRecordingsChanged: canvas.requestPaint()
    onViewStartChanged: canvas.requestPaint()
    onViewEndChanged: canvas.requestPaint()
    onContentWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
