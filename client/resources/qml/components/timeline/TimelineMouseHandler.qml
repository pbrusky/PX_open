import QtQuick 2.15

Item {
    id: mouseHandler

    signal moved()
    signal pressed()
    signal released()
    signal seekRequested(real tsMs)
    signal hoverTimeChanged(real tsMs)

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
        if (!hoverPreview)
            return
        hoverPreview.tsString = Qt.formatDateTime(new Date(tsMs), "hh:mm:ss")
        hoverPreview.dateString = Qt.formatDateTime(new Date(tsMs), "ddd MMM dd")
        if (hoverPreview.hasOwnProperty("lineHeight"))
            hoverPreview.lineHeight = trackHeight + 8
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

        onPositionChanged: function(mouse) {
            mouseHandler.moved()

            if (!xToTimestamp)
                return

            var ts = xToTimestamp(mouse.x)
            mouseHandler.hoverTimeChanged(ts)

            if (hoverPreview) {
                hoverPreview.visible = true
                // Keep bubble on screen
                var bx = mouse.x - hoverPreview.width / 2
                if (bx < 4)
                    bx = 4
                if (bx + hoverPreview.width > mouseHandler.width - 4)
                    bx = mouseHandler.width - hoverPreview.width - 4
                hoverPreview.x = bx
                hoverPreview.y = -hoverPreview.height + 2
                mouseHandler.formatHover(ts)
            }

            if (mouse.buttons & Qt.RightButton) {
                pan = mouseHandler.startPan + (mouse.x - mouseHandler.startX)
            }
        }

        onPressed: function(mouse) {
            mouseHandler.didSeek = false
            mouseHandler.pressed()

            if (mouse.button === Qt.RightButton) {
                mouseHandler.startPan = pan
                mouseHandler.startX = mouse.x
            }
        }

        onReleased: function(mouse) {
            mouseHandler.released()

            if (mouse.button === Qt.LeftButton && !mouseHandler.didSeek) {
                mouseHandler.didSeek = true
                if (xToTimestamp)
                    mouseHandler.seekRequested(xToTimestamp(mouse.x))
            }
            // Keep time visible briefly after click; hide on exit
        }

        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton && !mouseHandler.didSeek) {
                mouseHandler.didSeek = true
                if (xToTimestamp)
                    mouseHandler.seekRequested(xToTimestamp(mouse.x))
            }
        }

        onExited: {
            if (hoverPreview)
                hoverPreview.visible = false
            mouseHandler.hoverTimeChanged(-1)
        }
    }
}