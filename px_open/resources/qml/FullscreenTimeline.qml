import QtQuick 2.15
import QtQuick.Controls 2.15

import "components/timeline"

Rectangle {
    id: timeline
    width: parent.width
    height: collapsed ? 0 : 90
    color: "#0E0E0E"
    border.color: "#333333"
    border.width: 1
    radius: 6
    z: 10
    clip: true

    // Correct alias
    property alias timelineHeight: timeline.height

    //
    // REQUIRED for TimelineAutoHide
    //
    property var scrubber
    property var mouseHandler

    //
    // Collapse state
    //
    property bool collapsed: false
    function toggle() { collapsed = !collapsed }

    Behavior on height {
        NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
    }

    //
    // Provided by FullscreenCamera
    //
    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0
    property real position: 0

    property real startTs: 0
    property real endTs: 0

    //
    // Live clock
    //
    property int currentTimeMs: Date.now()
    Timer {
        id: nowTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

    //
    // Backend updates
    //
    Connections {
        target: frigateRef ? frigateRef : null
        ignoreUnknownSignals: true

        function onRecordingsLoaded(id, segments) {
            if (id !== cameraId) return
            recordings = segments
            if (segments.length > 0) {
                startTs = segments[0].start
                endTs = segments[segments.length - 1].end
            }
        }

        function onEventsLoaded(id, list) {
            if (id !== cameraId) return
            events = list
        }

        function onPlaybackPositionChanged(id, posMs) {
            if (id !== cameraId) return
            playbackPositionMs = posMs
            timeline.position = timeline.timestampToRatio(posMs)
            scrubber.x = timeline.timestampToX(posMs) - scrubber.width/2
        }
    }

    //
    // Timestamp conversion
    //
    function effectiveStartTs() {
        if (endTs > startTs) return startTs
        return Date.now() / 1000 - 3600
    }

    function effectiveEndTs() {
        if (endTs > startTs) return endTs
        return Date.now() / 1000
    }

    function timestampToRatio(tsMs) {
        if (effectiveEndTs() <= effectiveStartTs()) return 0
        return (tsMs - effectiveStartTs()*1000) /
               ((effectiveEndTs()-effectiveStartTs())*1000)
    }

    function ratioToTimestamp(ratio) {
        return effectiveStartTs()*1000 +
               ratio*(effectiveEndTs()-effectiveStartTs())*1000
    }

    onPositionChanged: playbackPositionMs = ratioToTimestamp(position)

    //
    // Zoom + Pan
    //
    property real zoom: 1.0
    property real pan: 0.0
    property real minZoom: 0.2
    property real maxZoom: 8.0
    property int segmentCount: 10

    function timestampToX(tsMs) {
        if (endTs <= startTs) return 0
        let totalMs = (endTs - startTs)*1000
        let ratio = (tsMs - startTs*1000) / totalMs
        return ratio * width * zoom + pan
    }

    function xToTimestamp(x) {
        let scaled = (x - pan) / (width * zoom)
        return (effectiveStartTs() + scaled*(effectiveEndTs()-effectiveStartTs())) * 1000
    }

    //
    // Ruler
    //
    TimelineRuler {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        segmentCount: timeline.segmentCount
    }

    //
    // Segments
    //
    TimelineSegments {
        id: segments
        recordings: timeline.recordings
        startTs: timeline.startTs
        endTs: timeline.endTs
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        anchors.top: ruler.bottom
    }

    //
    // Events
    //
    TimelineEvents {
        id: eventsLayer
        events: timeline.events
        startTs: timeline.startTs
        endTs: timeline.endTs
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        anchors.top: ruler.bottom
    }

    //
    // Scrubber
    //
    TimelineScrubber {
        id: scrubber
        playbackPositionMs: timeline.playbackPositionMs
        startTs: timeline.startTs
        endTs: timeline.endTs
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
    }

    //
    // Hover preview
    //
    TimelineHoverPreview { id: hoverPreview }

    //
    // Mouse interaction
    //
    TimelineMouseHandler {
        id: mouseHandler
        scrubber: scrubber
        hoverPreview: hoverPreview
        pan: timeline.pan
        xToTimestamp: timeline.xToTimestamp
    }

    //
    // Live time indicator
    //
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

    //
    // Empty state
    //
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

    //
    // Auto-hide module
    //
    TimelineAutoHide {
        id: autoHide
        timeline: timeline
        scrubber: scrubber
        mouseHandler: mouseHandler
    }

    //
    // Expose scrubber + mouseHandler to FullscreenCamera
    //
    Component.onCompleted: {
        timeline.scrubber = scrubber
        timeline.mouseHandler = mouseHandler
    }
}
