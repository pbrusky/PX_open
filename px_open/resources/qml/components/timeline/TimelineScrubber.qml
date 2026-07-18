import QtQuick 2.15

Rectangle {
    id: scrubber

    //
    // Signals TimelineAutoHide listens to
    //
    signal moved()
    signal pressed()
    signal released()

    //
    // Properties
    //
    property real playbackPositionMs
    property real startTs
    property real endTs
    property real zoom
    property real pan
    property real timelineWidth
    property var timestampToX

    width: Math.max(8, 10 * zoom)
    height: parent.height
    radius: 3
    color: "#FFFFFF"
    border.color: "#CCCCCC"
    border.width: 1
    z: 50

    x: timestampToX(playbackPositionMs) - width/2

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 2
        height: parent.height
        color: "#BBBBBB"
    }

    MouseArea {
        anchors.fill: parent
        drag.target: scrubber

        onPressed: {
            scrubber.pressed()
        }

        onReleased: {
            scrubber.released()
        }

        onPositionChanged: {
            scrubber.moved()
        }
    }
}
