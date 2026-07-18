import QtQuick 2.15

Item {
    id: mouseHandler

    //
    // Signals TimelineAutoHide listens to
    //
    signal moved()
    signal pressed()
    signal released()

    //
    // REQUIRED PROPERTIES
    //
    property real pan
    property var scrubber
    property var hoverPreview
    property var xToTimestamp

    property real startPan: 0
    property real startX: 0

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        drag.target: scrubber

        onPositionChanged: function(mouse) {
            mouseHandler.moved()

            let ts = xToTimestamp(mouse.x)
            hoverPreview.visible = true
            hoverPreview.x = mouse.x - hoverPreview.width/2
            hoverPreview.y = -hoverPreview.height - 4

            hoverPreview.tsString = Qt.formatDateTime(new Date(ts), "hh:mm:ss ap")

            if (mouse.buttons & Qt.RightButton) {
                pan = mouseHandler.startPan + (mouse.x - mouseHandler.startX)
            }
        }

        onPressed: function(mouse) {
            mouseHandler.pressed()

            if (mouse.button === Qt.RightButton) {
                mouseHandler.startPan = pan
                mouseHandler.startX = mouse.x
            }
        }

        onReleased: {
            mouseHandler.released()
        }

        onExited: {
            hoverPreview.visible = false
        }
    }
}
