import QtQuick 2.15
import "qrc:/app/resources/qml/components"

Item {
    id: segments

    property var recordings: []
    property var timeline: null
    property real viewStart: 0
    property real viewEnd: 0
    property real contentWidth: 1

    readonly property bool hasValidView: viewStart >= 0 && viewEnd > viewStart

    function mapX(tsMs) {
        var s = viewStart
        var e = viewEnd
        var w = Math.max(1, contentWidth)
        if (!hasValidView)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    Repeater {
        model: segments.recordings

        Rectangle {
            id: segment
            property real recordingStart: {
                var start = Number(modelData.start)
                return isFinite(start) && start >= 0 ? start : 0
            }
            property real recordingEnd: {
                var end = Number(modelData.end)
                return isFinite(end) && end > 0 ? end : recordingStart
            }
            property real segmentX1: segments.mapX(recordingStart * 1000)
            property real segmentX2: segments.mapX(recordingEnd * 1000)

            height: Math.max(8, segments.height * 0.35)
            y: segments.height - height - 2
            width: Math.max(2, segmentX2 - segmentX1)
            x: segmentX1
            radius: 1
            color: NxStyle.recording
            opacity: 0.85
            visible: segments.hasValidView && recordingEnd > recordingStart && segmentX2 >= segmentX1
        }
    }
}
