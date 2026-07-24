import QtQuick 2.15

Item {
    id: segments

    // REQUIRED PROPERTIES
    property var recordings
    property real startTs
    property real endTs
    property real zoom
    property real pan
    property real timelineWidth
    property var timestampToX   // <-- FIXED

    Repeater {
        model: recordings

        Rectangle {
            height: 62
            y: 24
            radius: 4
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
                let x1 = timestampToX(modelData.start * 1000)
                let x2 = timestampToX(modelData.end * 1000)
                return Math.max(8, x2 - x1)
            }

            x: timestampToX(modelData.start * 1000)
        }
    }
}
