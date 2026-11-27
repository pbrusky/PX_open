import QtQuick 2.15
import "qrc:/app/resources/qml/components"

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

    Repeater {
        model: recordings

        Rectangle {
            height: Math.max(8, (parent ? parent.height : 28) * 0.35)
            y: parent ? (parent.height - height - 2) : 0
            radius: 1
            color: NxStyle.recording
            opacity: 0.85

            width: {
                var x1 = segments.mapX(Number(modelData.start) * 1000)
                var x2 = segments.mapX(Number(modelData.end) * 1000)
                return Math.max(2, x2 - x1)
            }
            x: segments.mapX(Number(modelData.start) * 1000)
        }
    }
}
