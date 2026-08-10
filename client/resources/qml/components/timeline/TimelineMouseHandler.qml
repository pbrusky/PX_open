import QtQuick 2.15

Item {
    id: mouseHandler

    signal moved()
    signal pressed()
    signal released()
    signal seekRequested(real tsMs)

    property real pan
    property var scrubber
    property var hoverPreview
    property var xToTimestamp

    property real startPan: 0
    property real startX: 0
    property bool didSeek: false

    anchors.fill: parent

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        // Do not use drag.target on scrubber — that can swallow the click

        onPositionChanged: function(mouse) {
            mouseHandler.moved()

            if (!xToTimestamp)
                return

            var ts = xToTimestamp(mouse.x)
            if (hoverPreview) {
                hoverPreview.visible = true
                hoverPreview.x = mouse.x - hoverPreview.width / 2
                hoverPreview.y = -hoverPreview.height - 4
                if (hoverPreview.hasOwnProperty("tsString"))
                    hoverPreview.tsString = Qt.formatDateTime(new Date(ts), "hh:mm:ss ap")
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

            if (hoverPreview)
                hoverPreview.visible = false
        }

        onClicked: function(mouse) {
            // Backup path if release did not fire seek
            if (mouse.button === Qt.LeftButton && !mouseHandler.didSeek) {
                mouseHandler.didSeek = true
                if (xToTimestamp)
                    mouseHandler.seekRequested(xToTimestamp(mouse.x))
            }
        }

        onExited: {
            if (hoverPreview)
                hoverPreview.visible = false
        }
    }
}