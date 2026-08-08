import QtQuick 2.15

Item {
    id: mouseHandler
    anchors.fill: parent

    signal moved()
    signal pressed()
    signal released()
    signal seekRequested(real timestampMs)

    property real pan
    property var scrubber
    property var hoverPreview
    property var xToTimestamp

    property real startPan: 0
    property real startX: 0
    property bool didSeek: false

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

        onPositionChanged: function(mouse) {
            mouseHandler.moved()

            if (typeof xToTimestamp === "function" && hoverPreview) {
                var ts = xToTimestamp(mouse.x)
                hoverPreview.visible = true
                hoverPreview.x = mouse.x - hoverPreview.width / 2
                hoverPreview.y = -hoverPreview.height - 4
                if (hoverPreview.tsString !== undefined)
                    hoverPreview.tsString = Qt.formatDateTime(new Date(ts), "hh:mm:ss ap")
            }

            if ((mouse.buttons & Qt.LeftButton) && scrubber)
                scrubber.x = mouse.x - scrubber.width / 2

            if (mouse.buttons & Qt.RightButton)
                pan = mouseHandler.startPan + (mouse.x - mouseHandler.startX)
        }

        onPressed: function(mouse) {
            mouseHandler.pressed()
            mouseHandler.didSeek = false
            if (mouse.button === Qt.RightButton) {
                mouseHandler.startPan = pan
                mouseHandler.startX = mouse.x
            } else if (mouse.button === Qt.LeftButton && scrubber) {
                scrubber.x = mouse.x - scrubber.width / 2
            }
        }

        // ONLY seek on release (once)
        onReleased: function(mouse) {
            mouseHandler.released()
            if (mouse.button === Qt.LeftButton
                    && !mouseHandler.didSeek
                    && typeof xToTimestamp === "function") {
                mouseHandler.didSeek = true
                var ts = xToTimestamp(mouse.x)
                mouseHandler.seekRequested(ts)
            }
        }

        onExited: {
            if (hoverPreview)
                hoverPreview.visible = false
        }
    }
}