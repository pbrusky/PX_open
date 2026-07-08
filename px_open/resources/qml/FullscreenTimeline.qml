import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: timeline
    height: 90
    width: parent.width

    // NX Witness timeline background
    color: "#0E0E0E"
    border.color: "#333333"
    border.width: 1
    radius: 6
    z: 10

    // Properties provided by ServerView
    signal scrubbed(real ratio, int timestampMs)
    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0
    property real position: 0
    property int currentTimeMs: Date.now()

    // start/end timestamps (seconds)
    property real startTs: 0
    property real endTs: 0

    Timer {
        id: nowTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

    function timestampToRatio(tsMs) {
        if (effectiveEndTs() <= effectiveStartTs())
            return 0

        return (tsMs - effectiveStartTs() * 1000) / ((effectiveEndTs() - effectiveStartTs()) * 1000)
    }

    function ratioToTimestamp(ratio) {
        return effectiveStartTs() * 1000 + ratio * (effectiveEndTs() - effectiveStartTs()) * 1000
    }

    onPositionChanged: {
        playbackPositionMs = ratioToTimestamp(position)
    }

    // zoom + pan
    property real zoom: 1.0
    property real pan: 0.0
    property real minZoom: 0.2
    property real maxZoom: 8.0
    property int segmentCount: 10

    // Timestamp -> X coordinate
    function timestampToX(tsMs) {
        if (endTs <= startTs)
            return 0

        let totalMs = (endTs - startTs) * 1000
        let ratio = (tsMs - startTs * 1000) / totalMs
        let scaled = ratio * width * zoom
        return scaled + pan
    }

    // X coordinate -> timestamp
    function effectiveStartTs() {
        if (endTs > startTs)
            return startTs
        return Date.now() / 1000 - 3600
    }

    function effectiveEndTs() {
        if (endTs > startTs)
            return endTs
        return Date.now() / 1000
    }

    function xToTimestamp(x) {
        let scaled = (x - pan) / (width * zoom)
        let ts = effectiveStartTs() + scaled * (effectiveEndTs() - effectiveStartTs())
        return ts * 1000
    }

    // Time ruler and tick marks
    Item {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 20

        property int segments: timeline.segmentCount

        Repeater {
            model: timeline.segmentCount + 1

            Rectangle {
                width: parent.width / (ruler.segments + 1)
                height: parent.height
                color: "transparent"

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0,0,width,height)
                        ctx.strokeStyle = "#4A4A4A"
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(width/2, height)
                        ctx.lineTo(width/2, height-8)
                        ctx.stroke()
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 0
                    font.pixelSize: 10
                    color: "#DDDDDD"
                    text: {
                        if (effectiveEndTs() <= effectiveStartTs()) return ""
                        let frac = index / timeline.segmentCount
                        let ts = effectiveStartTs() * 1000 + frac * (effectiveEndTs() - effectiveStartTs()) * 1000
                        return Qt.formatDateTime(new Date(ts), "hh:mm")
                    }
                }
            }
        }
    }

    // Recording segments
    Repeater {
        model: recordings

        Rectangle {
            height: timeline.height - 28
            y: 24
            color: "transparent"
            radius: 4
            border.color: "#3A8DFFAA"
            border.width: 1
            clip: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#3A8DFF88" }
                    GradientStop { position: 1.0; color: "#2E6BFF44" }
                }
            }

            width: {
                let x1 = timeline.timestampToX(modelData.start * 1000)
                let x2 = timeline.timestampToX(modelData.end * 1000)
                return Math.max(8, x2 - x1)
            }

            x: timeline.timestampToX(modelData.start * 1000)
        }
    }

    Rectangle {
        id: emptyState
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: ruler.bottom
        anchors.bottom: scrubber.top
        color: "transparent"
        visible: cameraId === "" || (recordings.length === 0 && events.length === 0)

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: cameraId === "" ? "No camera selected" : "No recordings or events available"
                color: "#AAAAAA"
                font.pixelSize: 12
                font.bold: cameraId === ""
            }
            Text {
                text: cameraId === "" ? "Select a camera to show timeline" : "Use Live playback or select another camera"
                color: "#777777"
                font.pixelSize: 10
            }
        }
    }

    // Current live time indicator
    Rectangle {
        width: 2
        height: parent.height
        color: "#FF4444"
        anchors.right: parent.right
        opacity: (cameraId === "" || effectiveEndTs() <= effectiveStartTs()) ? 0 : 0.35
        z: 20
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: Qt.formatDateTime(new Date(currentTimeMs), "hh:mm:ss")
        color: "#FF4444"
        font.pixelSize: 10
        opacity: cameraId === "" ? 0 : 0.8
        z: 21
    }

    // Event markers
    Repeater {
        model: events

        Item {
            width: 16
            height: 22
            x: timeline.timestampToX(modelData.start * 1000) - width/2
            y: 2

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0,0,width,height)
                    ctx.fillStyle = "#FF5C5C"
                    ctx.beginPath()
                    ctx.moveTo(width/2, 0)
                    ctx.lineTo(width, height)
                    ctx.lineTo(0, height)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }

    // Scrubber
    Rectangle {
        id: scrubber
        width: Math.max(8, 10 * timeline.zoom)
        height: timeline.height
        radius: 3
        color: "#FFFFFF"
        border.color: "#CCCCCC"
        border.width: 1
        x: timeline.timestampToX(playbackPositionMs) - width/2
        z: 50

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: 2
            height: parent.height
            color: "#BBBBBB"
        }

        MouseArea {
            anchors.fill: parent
            drag.target: parent
            cursorShape: Qt.SizeHorCursor

            onPressed: {
                let ts = timeline.xToTimestamp(parent.x + parent.width/2)
                playbackPositionMs = ts
                if (frigateRef) frigateRef.startPlayback(cameraId, ts)
            }

            onPositionChanged: function(mouse) {
                if (mouse.buttons & Qt.LeftButton) {
                    let ts = timeline.xToTimestamp(parent.x + parent.width/2)
                    playbackPositionMs = ts
                    if (frigateRef) frigateRef.startPlayback(cameraId, ts)
                }
            }

            onReleased: {
                let ts = timeline.xToTimestamp(parent.x + parent.width/2)
                playbackPositionMs = ts
                if (frigateRef) frigateRef.startPlayback(cameraId, ts)
            }
        }
    }

    // Hover preview
    Rectangle {
        id: hoverPreview
        width: 120
        height: 28
        radius: 4
        color: "#000000DD"
        border.color: "#888888"
        border.width: 1
        visible: false
        z: 100

        Text {
            anchors.centerIn: parent
            color: "white"
            font.pixelSize: 11
            text: hoverPreview.tsString
        }

        property string tsString: ""
    }

    // Mouse interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        drag.target: scrubber

        property real startPan: 0
        property real startX: 0

        // Hover + pan
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

        // Scrub start
        onPressed: function(mouse) {
            let ts = xToTimestamp(mouse.x)
            scrubber.x = mouse.x - scrubber.width/2
            playbackPositionMs = ts
            if (frigateRef)
                frigateRef.startPlayback(cameraId, ts)
            mouseArea.startPan = pan
            mouseArea.startX = mouse.x
            if (cameraId && cameraId !== "") {
                let ratio = timestampToRatio(ts)
                timeline.scrubbed(ratio, ts)
            }
        }

        // Scrub end
        onReleased: function(mouse) {
            let ts = xToTimestamp(mouse.x)
            playbackPositionMs = ts
            if (frigateRef)
                frigateRef.startPlayback(cameraId, ts)
        }

        onDoubleClicked: function(mouse) {
            if (frigateRef && cameraId && cameraId !== "")
                frigateRef.switchToLive(cameraId)
        }

        onWheel: function(wheel) {
            let delta = wheel.angleDelta.y > 0 ? 1.12 : 0.88
            if (wheel.modifiers & Qt.ShiftModifier)
                delta = wheel.angleDelta.y > 0 ? 1.3 : 0.7

            zoom = Math.max(minZoom, Math.min(maxZoom, zoom * delta))
            let cursorTs = xToTimestamp(wheel.x)
            let newX = timestampToX(cursorTs)
            pan += wheel.x - newX
        }
    }

    // Backend signals
    Connections {
        target: frigateRef ? frigateRef : null
        ignoreUnknownSignals: true

        function onRecordingsLoaded(receivedCameraId, segments) {
            if (receivedCameraId !== cameraId)
                return

            recordings = segments
            if (segments.length > 0) {
                startTs = segments[0].start
                endTs = segments[segments.length - 1].end
            }
        }

        function onEventsLoaded(receivedCameraId, eventsList) {
            if (receivedCameraId !== cameraId)
                return

            events = eventsList
        }

        function onPlaybackPositionChanged(receivedCameraId, positionMs) {
            if (receivedCameraId !== cameraId)
                return

            playbackPositionMs = positionMs
            scrubber.x = timeline.timestampToX(positionMs) - scrubber.width/2
        }

        function onCameraEditResult(ok, message) {
            if (!ok) return
            if (frigateRef) {
                frigateRef.loadEvents(cameraId)
                frigateRef.loadRecordings(cameraId)
            }
        }
    }
}
