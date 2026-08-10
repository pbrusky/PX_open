import QtQuick 2.15

Item {
    id: ruler
    property real startTs
    property real endTs
    property int segmentCount: 12

    anchors.left: parent.left
    anchors.right: parent.right
    height: 22

    function labelFor(index) {
        if (endTs <= startTs)
            return ""
        var frac = index / segmentCount
        var tsMs = (startTs + frac * (endTs - startTs)) * 1000
        var spanSec = endTs - startTs
        // Short range → show seconds; multi-hour → date + time
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
                height: index % 2 === 0 ? 10 : 6
                color: "#666666"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                font.pixelSize: 10
                color: "#CCCCCC"
                text: ruler.labelFor(index)
                // Hide edge labels that would clip
                visible: index > 0 && index < segmentCount
            }
        }
    }

    // Always show start / end clearly
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.top: parent.top
        font.pixelSize: 10
        font.bold: true
        color: "#FFFFFF"
        text: ruler.labelFor(0)
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: parent.top
        font.pixelSize: 10
        font.bold: true
        color: "#FFFFFF"
        text: ruler.labelFor(segmentCount)
    }
}