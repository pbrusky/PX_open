import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: timeline
    height: 80
    width: parent.width

    // NX Witness timeline background
    color: "black"
    z: 10

    //
    // Properties provided by ServerView
    //
    property string cameraName: ""
    property var frigateRef
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0

    // start/end timestamps (seconds)
    property real startTs: 0
    property real endTs: 0

    // zoom + pan
    property real zoom: 1.0
    property real pan: 0.0
    property real minZoom: 0.1
    property real maxZoom: 10.0

    //
    // Timestamp → X coordinate
    //
    function timestampToX(tsMs) {
        if (endTs <= startTs)
            return 0

        let totalMs = (endTs - startTs) * 1000
        let ratio = (tsMs - startTs * 1000) / totalMs
        let scaled = ratio * width * zoom
        return scaled + pan
    }

    //
    // X coordinate → timestamp
    //
    function xToTimestamp(x) {
        let scaled = (x - pan) / (width * zoom)
        let ts = startTs + scaled * (endTs - startTs)
        return ts * 1000
    }

    //
    // Recording segments
    //
    Repeater {
        model: recordings

        Rectangle {
            height: timeline.height
            y: 0
            color: "#3A8DFF55"

            width: {
                let x1 = timeline.timestampToX(modelData.start * 1000)
                let x2 = timeline.timestampToX(modelData.end * 1000)
                return Math.max(2, x2 - x1)
            }

            x: timeline.timestampToX(modelData.start * 1000)
        }
    }

    //
    // Event markers
    //
    Repeater {
        model: events

        Rectangle {
            width: 3 * timeline.zoom
            height: timeline.height
            color: "#FF4444"
            x: timeline.timestampToX(modelData.start * 1000)
        }
    }

    //
    // Scrubber
    //
    Rectangle {
        id: scrubber
        width: 2 * timeline.zoom
        height: timeline.height
        color: "white"
        x: timeline.timestampToX(playbackPositionMs)
    }

    //
    // Hover preview
    //
    Rectangle {
        id: hoverPreview
        width: 120
        height: 30
        radius: 4
        color: "#000000CC"
        visible: false

        Text {
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 12
            text: hoverPreview.tsString
        }

        property string tsString: ""
    }

    //
    // Mouse interaction
    //
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        drag.target: scrubber

        property real startPan: 0
        property real startX: 0

        //
        // Hover + pan
        //
        onPositionChanged: function(mouse) {
            let ts = xToTimestamp(mouse.x)
            hoverPreview.visible = true
            hoverPreview.x = mouse.x - hoverPreview.width/2
            hoverPreview.y = -hoverPreview.height - 4

            let d = new Date(ts)
            hoverPreview.tsString = Qt.formatDateTime(d, "hh:mm:ss ap")

            if (mouse.buttons & Qt.RightButton) {
                pan = mouseArea.startPan + (mouse.x - mouseArea.startX)
            }
        }

        onExited: hoverPreview.visible = false

        //
        // Scrub start
        //
        onPressed: function(mouse) {
            let ts = xToTimestamp(mouse.x)
            scrubber.x = mouse.x
            playbackPositionMs = ts

            if (frigateRef)
                frigateRef.startPlayback(cameraName, ts)

            mouseArea.startPan = pan
            mouseArea.startX = mouse.x
        }

        //
        // Scrub end
        //
        onReleased: function(mouse) {
            let ts = xToTimestamp(mouse.x)
            playbackPositionMs = ts

            if (frigateRef)
                frigateRef.startPlayback(cameraName, ts)
        }

        //
        // Double-click → LIVE
        //
        onDoubleClicked: function(mouse) {
            if (frigateRef)
                frigateRef.switchToLive(cameraName)
        }

        //
        // Zoom
        //
        onWheel: function(wheel) {
            let delta = wheel.angleDelta.y > 0 ? 1.1 : 0.9
            if (wheel.modifiers & Qt.ShiftModifier)
                delta = wheel.angleDelta.y > 0 ? 1.25 : 0.75

            zoom = Math.max(minZoom, Math.min(maxZoom, zoom * delta))

            let cursorTs = xToTimestamp(wheel.x)
            let newX = timestampToX(cursorTs)
            pan += wheel.x - newX
        }
    }

    //
    // Backend signals
    //
    Connections {
        target: frigateRef ? frigateRef : null
        ignoreUnknownSignals: true

        function onRecordingsLoaded(cameraId, segments) {
            if (cameraId !== cameraName)
                return

            recordings = segments

            if (segments.length > 0) {
                startTs = segments[0].start
                endTs = segments[segments.length - 1].end
            }
        }

        function onEventsLoaded(cameraId, eventsList) {
            if (cameraId !== cameraName)
                return

            events = eventsList
        }

        function onPlaybackPositionChanged(cameraId, positionMs) {
            if (cameraId !== cameraName)
                return

            playbackPositionMs = positionMs
            scrubber.x = timestampToX(positionMs)
        }

        function onCameraEditResult(ok, message) {
            if (!ok) return

            if (frigateRef) {
                frigateRef.loadEvents(cameraName)
                frigateRef.loadRecordings(cameraName)
            }
        }
    }
}
