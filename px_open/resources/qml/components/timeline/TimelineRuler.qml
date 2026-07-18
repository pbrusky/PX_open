import QtQuick 2.15

Item {
    id: ruler
    property real startTs
    property real endTs
    property int segmentCount: 10

    anchors.left: parent.left
    anchors.right: parent.right
    height: 20

    Repeater {
        model: segmentCount + 1

        Rectangle {
            width: parent.width / (segmentCount + 1)
            height: parent.height
            color: "transparent"

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0,0,width,height)
                    ctx.strokeStyle = "#4A4A4A"
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(width/2, height)
                    ctx.lineTo(width/2, height-8)
                    ctx.stroke()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                font.pixelSize: 10
                color: "#DDDDDD"
                text: {
                    if (endTs <= startTs) return ""
                    let frac = index / segmentCount
                    let ts = startTs * 1000 +
                             frac * (endTs - startTs) * 1000
                    return Qt.formatDateTime(new Date(ts), "hh:mm")
                }
            }
        }
    }
}
