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
            height: parent ? parent.height : 28
            y: 0
            radius: 3
            border.color: "#3A8DFFAA"
            border.width: 1
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#3A8DFF88" }
                    GradientStop { position: 1.0; color: "#2E6BFF44" }
                }
            }

            width: {
                if (!timestampToX)
                    return 8
                var x1 = timestampToX(modelData.start * 1000)
                var x2 = timestampToX(modelData.end * 1000)
                return Math.max(8, x2 - x1)
            }

            x: timestampToX ? timestampToX(modelData.start * 1000) : 0
        }
    }
}