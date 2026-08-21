import QtQuick 2.15

Item {
    id: ruler
    property real startTs
    property real endTs
    property int segmentCount: 12
    property int labelPixelSize: 14   // was 10 — increase further if needed

    anchors.left: parent.left
    anchors.right: parent.right
    height: 28                        // was 22 — room for larger text

    function labelFor(index) {
        if (endTs <= startTs)
            return ""
        var frac = index / segmentCount
        var tsMs = (startTs + frac * (endTs - startTs)) * 1000
        var spanSec = endTs - startTs
        if (spanSec <= 3600)
            return Qt.formatDateTime(new Date(tsMs), "hh:mm:ss")
        if (spanSec <= 24 * 3600)
            return Qt.formatDateTime(new Date(tsMs), "hh:mm")
        return Qt.formatDateTime(new Date(tsMs), "MM/dd hh:mm")
    }

    Repeater {
        model: segmentCount + 1

        Item {
            width: ruler.width / segmentCount
            height: ruler.height
            x: index * (ruler.width / segmentCount) - width / 2

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: 1
                height: index % 2 === 0 ? 12 : 7
                color: "#666666"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                font.pixelSize: ruler.labelPixelSize
                font.bold: false
                color: "#EEEEEE"
                text: ruler.labelFor(index)
                visible: index > 0 && index < segmentCount
            }
        }
    }

    // Start / end — slightly bolder and same size
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.top: parent.top
        font.pixelSize: ruler.labelPixelSize
        font.bold: true
        color: "#FFFFFF"
        text: ruler.labelFor(0)
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        font.pixelSize: ruler.labelPixelSize
        font.bold: true
        color: "#FFFFFF"
        text: ruler.labelFor(segmentCount)
    }
}