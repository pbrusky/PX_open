import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent ? parent.width : 800

    property bool collapsed: true
    property bool allowAutoReveal: false

    signal seekRequested(real timestampMs)

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

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0
    property real startTs: 0
    property real endTs: 0
    property bool isPlayback: false

    property int currentTimeMs: Date.now()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

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

    function timestampToX(tsMs) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        if (e <= s || width <= 0)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(width, ratio * width))
    }

    function xToTimestamp(x) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var ratio = Math.max(0, Math.min(1, x / Math.max(1, width)))
        return (s + ratio * (e - s)) * 1000
    }

    TimelineRuler {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        segmentCount: 10
        visible: !collapsed
    }

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
        anchors.fill: trackBg
        recordings: timeline.recordings
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        zoom: 1.0
        pan: 0
        timelineWidth: timeline.width
        timestampToX: timeline.timestampToX
        visible: !collapsed
    }

    // Scrubber playhead
    Rectangle {
        id: playhead
        width: 3
        height: trackBg.height + 6
        color: isPlayback ? "#FFC107" : "#FFFFFF"
        anchors.top: trackBg.top
        anchors.topMargin: -3
        x: {
            var ts = isPlayback && playbackPositionMs > 0
                     ? playbackPositionMs
                     : currentTimeMs
            return timestampToX(ts) - width / 2
        }
        visible: !collapsed
        z: 30
    }

    // Full bar is clickable; high z so nothing covers it
    TimelineMouseHandler {
        id: mouseHandler
        anchors.fill: parent
        z: 50
        scrubber: playhead
        hoverPreview: hoverPreview
        pan: 0
        xToTimestamp: timeline.xToTimestamp
        visible: !collapsed
        enabled: !collapsed

        onSeekRequested: function(tsMs) {
            timeline.playbackPositionMs = tsMs
            timeline.seekRequested(tsMs)
        }
    }

    TimelineHoverPreview {
        id: hoverPreview
        visible: false
        z: 60
    }

    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        text: Qt.formatDateTime(new Date(currentTimeMs), "hh:mm:ss")
        color: "#FF4444"
        font.pixelSize: 10
        opacity: collapsed ? 0 : 0.85
        z: 55
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        text: {
            if (collapsed)
                return ""
            if (isPlayback && playbackPositionMs > 0)
                return "REC  " + Qt.formatDateTime(new Date(playbackPositionMs), "hh:mm:ss")
            if (recordings.length > 0)
                return recordings.length + " recording block(s) — click to play"
            return "No recordings in range"
        }
        color: isPlayback ? "#FFC107" : "#888888"
        font.pixelSize: 10
        visible: !collapsed
        z: 55
    }
}