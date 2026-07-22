import QtQuick 2.15
import QtQuick.Controls 2.15

// Correct QRC import path
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent.width

    property bool collapsed: true
    property bool allowAutoReveal: false

    function showTimeline() {
        if (!allowAutoReveal) return
        collapsed = false
    }

    function hideTimeline() {
        collapsed = true
    }

    height: collapsed ? 0 : 90
    visible: true

    color: collapsed ? "transparent" : "#0E0E0E"
    border.color: collapsed ? "transparent" : "#333333"
    border.width: collapsed ? 0 : 1
    radius: collapsed ? 0 : 6

    z: 10
    clip: true

    property alias timelineHeight: timeline.height

    property var scrubber
    property var mouseHandler

    Behavior on height {
        NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
    }

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0
    property real position: 0

    property real startTs: 0
    property real endTs: 0

    property int currentTimeMs: Date.now()
    Timer {
        id: nowTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

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
            if (scrubber)
                scrubber.x = timeline.timestampToX(posMs) - scrubber.width/2
        }
    }

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

    TimelineRuler {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        segmentCount: timeline.segmentCount
        visible: !collapsed
    }

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
        visible: !collapsed
    }

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
        visible: !collapsed
    }

    TimelineScrubber {
        id: scrubber
        playbackPositionMs: timeline.playbackPositionMs
        startTs: timeline.startTs
        endTs: timeline.endTs
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        visible: !collapsed
    }

    TimelineHoverPreview {
        id: hoverPreview
        visible: !collapsed
    }

    TimelineMouseHandler {
        id: mouseHandler
        scrubber: scrubber
        hoverPreview: hoverPreview
        pan: timeline.pan
        xToTimestamp: timeline.xToTimestamp
        visible: !collapsed
    }

    Rectangle {
        width: 2
        height: parent.height
        color: "#FF4444"
        anchors.right: parent.right
        opacity: (cameraId === "" || effectiveEndTs() <= effectiveStartTs() || collapsed) ? 0 : 0.35
        z: 20
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: Qt.formatDateTime(new Date(currentTimeMs), "hh:mm:ss")
        color: "#FF4444"
        font.pixelSize: 10
        opacity: (cameraId === "" || collapsed) ? 0 : 0.8
        z: 21
    }

    Rectangle {
        id: emptyState
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: ruler.bottom
        anchors.bottom: scrubber.top
        color: "transparent"
        visible: !collapsed && (cameraId === "" || (recordings.length === 0 && events.length === 0))

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

    TimelineAutoHide {
        id: autoHide
        timeline: timeline

        onMouseNearBottom: timeline.showTimeline()
        onMouseAway: timeline.hideTimeline()
    }

    Component.onCompleted: {
        timeline.scrubber = scrubber
        timeline.mouseHandler = mouseHandler
    }
}
