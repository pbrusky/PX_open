import QtQuick 2.15

Item {
    id: segments

    property var recordings
    property real startTs
    property real endTs
    property real zoom
    property real pan
    property real timelineWidth
    property var timestampToX

    Repeater {
        model: recordings

        Rectangle {
            height: Math.max(8, (parent ? parent.height : 28) * 0.35)
            y: parent ? (parent.height - height - 2) : 0
            radius: 1
            color: "#2E7D32"
            opacity: 0.85

            width: {
                if (!timestampToX)
                    return 4
                var x1 = timestampToX(modelData.start * 1000)
                var x2 = timestampToX(modelData.end * 1000)
                return Math.max(2, x2 - x1)
            }
            x: timestampToX ? timestampToX(modelData.start * 1000) : 0
        }
    }
}