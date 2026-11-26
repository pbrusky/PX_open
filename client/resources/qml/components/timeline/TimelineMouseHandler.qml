import QtQuick 2.15

Item {
    id: mouseHandler

    signal moved()
    signal pressed()
    signal released()
    signal seekRequested(real tsMs)
    signal hoverTimeChanged(real tsMs)
    signal panChanged(real newPan)

    property real pan
    property var scrubber
    property var hoverPreview
    property var xToTimestamp
    property real trackHeight: 28

    property real startPan: 0
    property real startX: 0
    property bool didSeek: false

    anchors.fill: parent

    function formatHover(tsMs) {
        if (!hoverPreview || isNaN(tsMs) || tsMs <= 0)
            return

        // Reuse single Date instance or format efficiently
        var d = new Date(tsMs)
        hoverPreview.tsString = Qt.formatDateTime(d, "hh:mm:ss")
        hoverPreview.dateString = Qt.formatDateTime(d, "ddd MMM dd")
        
        // Qt 5/6 compatible property check
        if ("lineHeight" in hoverPreview)
            hoverPreview.lineHeight = trackHeight + 8
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

        onPositionChanged: function(mouse) {
            mouseHandler.moved()

            // Safe function check
            if (typeof mouseHandler.xToTimestamp !== "function")
                return

            var ts = mouseHandler.xToTimestamp(mouse.x)
            mouseHandler.hoverTimeChanged(ts)

            if (hoverPreview) {
                hoverPreview.visible = true
                
                // Keep bubble clamped within bounds
                var bx = mouse.x - hoverPreview.width / 2
                var maxX = mouseHandler.width - hoverPreview.width - 4
                bx = Math.max(4, Math.min(bx, maxX))

                hoverPreview.x = bx
                hoverPreview.y = -hoverPreview.height + 2
                mouseHandler.formatHover(ts)
            }

            if (mouse.buttons & Qt.RightButton) {
                var calculatedPan = mouseHandler.startPan + (mouse.x - mouseHandler.startX)
                mouseHandler.pan = calculatedPan
                mouseHandler.panChanged(calculatedPan)
            }
        }

        onPressed: function(mouse) {
            mouseHandler.didSeek = false
            mouseHandler.pressed()

            if (mouse.button === Qt.RightButton) {
                mouseHandler.startPan = mouseHandler.pan
                mouseHandler.startX = mouse.x
            }
        }

        onReleased: function(mouse) {
            mouseHandler.released()
            if (mouse.button === Qt.LeftButton && !mouseHandler.didSeek) {
                mouseHandler.didSeek = true
                if (typeof mouseHandler.xToTimestamp === "function") {
                    var ts = mouseHandler.xToTimestamp(mouse.x)
                    if (ts > 0)
                        mouseHandler.seekRequested(ts)
                }
            }
        }

        onExited: {
            if (hoverPreview)
                hoverPreview.visible = false
            mouseHandler.hoverTimeChanged(-1)
        }
    }
}