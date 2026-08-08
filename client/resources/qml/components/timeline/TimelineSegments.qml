import QtQuick 2.15

Item {
    id: segments
    anchors.fill: parent

    property var recordings: []
    property real startTs: 0
    property real endTs: 0
    property real zoom: 1.0
    property real pan: 0.0
    property real timelineWidth: width
    property var timestampToX

    // NX-style continuous recording track
    Repeater {
        model: recordings

        Rectangle {
            height: Math.max(16, parent ? parent.height - 2 : 16)
            y: 1
            radius: 2
            color: "#2F6FED"
            border.color: "#5B9BFF"
            border.width: 1

            width: {
                if (typeof timestampToX !== "function")
                    return Math.max(8, parent ? parent.width : 8)
                var x1 = timestampToX(Number(modelData.start) * 1000)
                var x2 = timestampToX(Number(modelData.end) * 1000)
                return Math.max(8, x2 - x1)
            }

            x: {
                if (typeof timestampToX !== "function")
                    return 0
                return timestampToX(Number(modelData.start) * 1000)
            }
        }
    }
}