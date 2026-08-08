import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent ? parent.width : 800

    property bool collapsed: true
    property bool allowAutoReveal: false

    function showTimeline() {
        if (!allowAutoReveal)
            return
        collapsed = false
    }

    function hideTimeline() {
        collapsed = true
    }

    height: collapsed ? 4 : 100
    visible: true
    color: collapsed ? "#00000000" : "#0E0E0E"
    border.color: collapsed ? "transparent" : "#333333"
    border.width: collapsed ? 0 : 1
    radius: collapsed ? 0 : 6
    z: 10
    clip: true

    property alias timelineHeight: timeline.height
    property var scrubber
    property var mouseHandler

    Behavior on height {
        NumberAnimation { duration: 160; easing.type: Easing.InOutQuad }
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
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

    // Also listen here (backup if parent misses signal)
    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onRecordingsLoaded(id, segments) {
            if (id !== cameraId && id !== cameraName)
                return
            recordings = segments
            if (segments && segments.length > 0) {
                startTs = segments[0].start
                endTs = segments[segments.length - 1].end
            }
        }

        function onEventsLoaded(id, list) {
            if (id !== cameraId && id !== cameraName)
                return
            events = list
        }

        function onPlaybackPositionChanged(id, posMs) {
            if (id !== cameraId && id !== cameraName)
                return
            playbackPositionMs = posMs
            position = timestampToRatio(posMs)
        }
    }

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

    function timestampToRatio(tsMs) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        if (e <= s)
            return 0
        return (tsMs - s * 1000) / ((e - s) * 1000)
    }

    function ratioToTimestamp(ratio) {
        return effectiveStartTs() * 1000 +
               ratio * (effectiveEndTs() - effectiveStartTs()) * 1000
    }

    onPositionChanged: playbackPositionMs = ratioToTimestamp(position)

    property real zoom: 1.0
    property real pan: 0.0
    property int segmentCount: 10

    function timestampToX(tsMs) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        if (e <= s || width <= 0)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return ratio * width * zoom + pan
    }

    function xToTimestamp(x) {
        var scaled = (x - pan) / Math.max(1, width * zoom)
        return (effectiveStartTs() + scaled * (effectiveEndTs() - effectiveStartTs())) * 1000
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

    // Track background (dark rail)
    Rectangle {
        id: trackBg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: ruler.bottom
        anchors.topMargin: 4
        height: 28
        color: "#1A1A1A"
        radius: 3
        visible: !collapsed
    }

    TimelineSegments {
        id: segmentsLayer
        anchors.fill: trackBg
        recordings: timeline.recordings
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        visible: !collapsed
    }

    TimelineEvents {
        id: eventsLayer
        anchors.fill: trackBg
        events: timeline.events
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        visible: !collapsed
    }

    TimelineScrubber {
        id: scrubber
        anchors.top: trackBg.top
        anchors.bottom: trackBg.bottom
        playbackPositionMs: timeline.playbackPositionMs
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        zoom: timeline.zoom
        pan: timeline.pan
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        visible: !collapsed
    }

    TimelineHoverPreview {
        id: hoverPreview
        visible: false
    }

    TimelineMouseHandler {
        id: mouseHandler
        anchors.fill: trackBg
        scrubber: scrubber
        hoverPreview: hoverPreview
        pan: timeline.pan
        xToTimestamp: timeline.xToTimestamp
        visible: !collapsed
        enabled: !collapsed
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: Qt.formatDateTime(new Date(currentTimeMs), "hh:mm:ss")
        color: "#FF4444"
        font.pixelSize: 10
        opacity: collapsed ? 0 : 0.85
        z: 21
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        text: {
            if (collapsed)
                return ""
            if (recordings.length > 0)
                return recordings.length + " recording block(s)"
            return "No recordings in range"
        }
        color: "#888888"
        font.pixelSize: 10
        visible: !collapsed
    }

    Rectangle {
        id: emptyState
        anchors.fill: trackBg
        color: "transparent"
        visible: !collapsed && cameraId !== "" && recordings.length === 0 && events.length === 0

        Text {
            anchors.centerIn: parent
            text: "No recordings or events available"
            color: "#AAAAAA"
            font.pixelSize: 12
        }
    }

    Component.onCompleted: {
        timeline.scrubber = scrubber
        timeline.mouseHandler = mouseHandler
    }
}