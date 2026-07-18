import QtQuick 2.15

Item {
    id: eventsLayer

    // REQUIRED PROPERTIES
    property var events
    property real startTs
    property real endTs
    property real zoom
    property real pan
    property real timelineWidth
    property var timestampToX   // <-- FIXED

    Repeater {
        model: events

        Item {
            width: 16
            height: 22
            x: timestampToX(modelData.start * 1000) - width/2
            y: 2

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0,0,width,height)
                    ctx.fillStyle = "#FF5C5C"
                    ctx.beginPath()
                    ctx.moveTo(width/2, 0)
                    ctx.lineTo(width, height)
                    ctx.lineTo(0, height)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }
}
