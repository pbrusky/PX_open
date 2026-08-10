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

    // Extra height so hover time sits above the track, not under it
    height: collapsed ? 4 : 150
    visible: true
    color: collapsed ? "#00000000" : "#0E0E0E"
    border.color: collapsed ? "transparent" : "#333333"
    border.width: collapsed ? 0 : 1
    radius: collapsed ? 0 : 6
    z: 10
    clip: false

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var recordings: []
    property var events: []
    property int playbackPositionMs: 0
    property real startTs: 0
    property real endTs: 0
    property bool isPlayback: false
    property real hoverTsMs: -1

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

    function formatFull(tsMs) {
        if (tsMs <= 0)
            return ""
        return Qt.formatDateTime(new Date(tsMs), "ddd MMM dd  hh:mm:ss")
    }

    // Large always-visible cursor / playback time (not clipped)
    Rectangle {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: collapsed ? 0 : 32
        color: "#161616"
        visible: !collapsed
        z: 20
        clip: false

        Text {
            id: statusTime
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (hoverTsMs > 0)
                    return "Cursor   " + formatFull(hoverTsMs)
                if (isPlayback && playbackPositionMs > 0)
                    return "Playback   " + formatFull(playbackPositionMs)
                return "Live   " + formatFull(currentTimeMs)
            }
            color: hoverTsMs > 0 ? "#FFC107" : (isPlayback ? "#FFC107" : "#00C853")
            font.pixelSize: 16
            font.bold: true
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: {
                var s = effectiveStartTs()
                var e = effectiveEndTs()
                return Qt.formatDateTime(new Date(s * 1000), "hh:mm:ss")
                       + "  →  "
                       + Qt.formatDateTime(new Date(e * 1000), "hh:mm:ss")
            }
            color: "#888888"
            font.pixelSize: 12
        }
    }

    TimelineRuler {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusBar.bottom
        anchors.topMargin: 2
        startTs: timeline.effectiveStartTs()
        endTs: timeline.effectiveEndTs()
        segmentCount: 12
        visible: !collapsed
        z: 5
    }

    Rectangle {
        id: trackBg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.top: ruler.bottom
        anchors.topMargin: 6
        height: 36
        color: "#1A1A1A"
        radius: 3
        visible: !collapsed
        border.color: "#333"
        border.width: 1
        z: 5
        clip: false
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
        z: 6
    }

    Item {
        id: playheadItem
        width: 3
        height: trackBg.height + 6
        anchors.top: trackBg.top
        anchors.topMargin: -3
        x: {
            var ts = isPlayback && playbackPositionMs > 0
                     ? playbackPositionMs
                     : currentTimeMs
            return trackBg.x + timestampToX(ts) - width / 2
        }
        visible: !collapsed
        z: 30

        Rectangle {
            anchors.fill: parent
            color: isPlayback ? "#FFC107" : "#FFFFFF"
        }
    }

    TimelineMouseHandler {
        id: mouseHandler
        anchors.fill: trackBg
        z: 50
        scrubber: playheadItem
        hoverPreview: null
        pan: 0
        xToTimestamp: function(x) {
            // x is relative to trackBg
            return timeline.xToTimestamp(x)
        }
        trackHeight: trackBg.height
        visible: !collapsed
        enabled: !collapsed

        onSeekRequested: function(tsMs) {
            timeline.playbackPositionMs = tsMs
            timeline.seekRequested(tsMs)
        }
        onHoverTimeChanged: function(tsMs) {
            timeline.hoverTsMs = tsMs
            if (tsMs > 0) {
                cursorLine.visible = true
                cursorLine.x = trackBg.x + timeline.timestampToX(tsMs) - 1
            } else {
                cursorLine.visible = false
            }
        }
    }

    // Vertical cursor line over the track
    Rectangle {
        id: cursorLine
        width: 2
        anchors.top: trackBg.top
        anchors.bottom: trackBg.bottom
        color: "#FFC107"
        opacity: 0.9
        visible: false
        z: 40
    }

    // Floating time label ABOVE the track (parent = timeline, not clipped by track)
    Rectangle {
        id: cursorBubble
        visible: !collapsed && hoverTsMs > 0
        z: 100
        width: cursorBubbleText.implicitWidth + 20
        height: 28
        radius: 6
        color: "#F0000000"
        border.color: "#FFC107"
        border.width: 1

        x: {
            var cx = trackBg.x + timeline.timestampToX(hoverTsMs) - width / 2
            if (cx < 4) cx = 4
            if (cx + width > timeline.width - 4)
                cx = timeline.width - width - 4
            return cx
        }
        // Sit in the gap between ruler and track (readable)
        y: trackBg.y - height - 4

        Text {
            id: cursorBubbleText
            anchors.centerIn: parent
            text: hoverTsMs > 0
                  ? Qt.formatDateTime(new Date(hoverTsMs), "MMM dd  hh:mm:ss")
                  : ""
            color: "#FFC107"
            font.pixelSize: 14
            font.bold: true
        }
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        text: {
            if (collapsed)
                return ""
            if (recordings.length > 0)
                return recordings.length + " recording block(s) — hover for time, click to play"
            return "No recordings in range"
        }
        color: "#777777"
        font.pixelSize: 10
        visible: !collapsed
        z: 5
    }
}