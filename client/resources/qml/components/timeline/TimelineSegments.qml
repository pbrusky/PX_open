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

    Repeater {
        model: recordings

        Rectangle {
            height: Math.max(12, parent.height - 4)
            y: 2
            radius: 3
            border.color: "#5BA3FF"
            border.width: 1
            clip: true

            gradient: Gradient {
                GradientStop { position: 0.0; color: "#3A8DFFAA" }
                GradientStop { position: 1.0; color: "#2E6BFF66" }
            }

            width: {
                if (!timestampToX)
                    return 8
                var x1 = timestampToX(modelData.start * 1000)
                var x2 = timestampToX(modelData.end * 1000)
                return Math.max(6, x2 - x1)
            }

            x: timestampToX ? timestampToX(modelData.start * 1000) : 0
        }
    }
}