import QtQuick 2.15

MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    drag.target: scrubber

    // REQUIRED PROPERTIES
    property real pan
    property var scrubber
    property var hoverPreview
    property var xToTimestamp   // <-- FIXED

    property real startPan: 0
    property real startX: 0

    onPositionChanged: function(mouse) {
        let ts = xToTimestamp(mouse.x)
        hoverPreview.visible = true
        hoverPreview.x = mouse.x - hoverPreview.width/2
        hoverPreview.y = -hoverPreview.height - 4

        hoverPreview.tsString = Qt.formatDateTime(new Date(ts), "hh:mm:ss ap")

        if (mouse.buttons & Qt.RightButton) {
            pan = mouseArea.startPan + (mouse.x - mouseArea.startX)
        }
    }

    onPressed: function(mouse) {
        if (mouse.button === Qt.RightButton) {
            mouseArea.startPan = pan
            mouseArea.startX = mouse.x
        }
    }

    onExited: {
        hoverPreview.visible = false
    }
}
