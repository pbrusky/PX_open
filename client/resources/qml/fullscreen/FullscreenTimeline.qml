import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent ? parent.width : 800

    property bool collapsed: true
    property bool allowAutoReveal: false
    property bool pointerInside: false

    // Raise this to show fewer orange ticks (10 = busy, 25 = default, 50–100 = strong only)
    property real minMotion: 25

    signal seekRequested(real timestampMs)
    signal hoverActiveChanged(bool active)

    function showTimeline() {
        if (!allowAutoReveal)
            return
        collapsed = false
    }

    function hideTimeline() {
        collapsed = true
        hoverTsMs = -1
        pointerInside = false
    }

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
    property var motionPoints: []
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

    HoverHandler {
        id: rootHover
        enabled: !collapsed
        onHoveredChanged: {
            pointerInside = hovered
            hoverActiveChanged(hovered)
            if (!hovered)
                hoverTsMs = -1
        }
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onRecordingsLoaded(id, segments) {
            if (id !== cameraId && id !== cameraName)
                return
            recordings = segments
            if (segments && segments.length > 0) {
                startTs = Number(segments[0].start)
                endTs = Number(segments[segments.length - 1].end)
            }
        }

        function onEventsLoaded(id, list) {
            if (id !== cameraId && id !== cameraName)
                return
            events = list
        }

        function onMotionActivityLoaded(id, points) {
            if (id !== cameraId && id !== cameraName)
                return
            applyMotionPoints(points)
        }

        function onPlaybackPositionChanged(id, posMs) {
            if (id !== cameraId && id !== cameraName)
                return
            playbackPositionMs = posMs
        }
    }

    function normalizeSec(t) {
        t = Number(t || 0)
        if (t > 100000000000)
            t = t / 1000
        return t
    }

    function applyMotionPoints(points) {
        motionPoints = points || []
        if (!motionPoints || motionPoints.length === 0)
            return

        var minT = startTs > 0 ? startTs : Number.MAX_VALUE
        var maxT = endTs > 0 ? endTs : 0
        for (var i = 0; i < motionPoints.length; ++i) {
            var p = motionPoints[i]
            var t = normalizeSec(p.start !== undefined ? p.start : p.start_time)
            if (t <= 0)
                continue
            if (t < minT) minT = t
            if (t > maxT) maxT = t
        }
        if (minT < Number.MAX_VALUE) {
            if (startTs <= 0 || minT < startTs)
                startTs = minT
            if (maxT > endTs)
                endTs = maxT
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
        var w = trackBg.width > 0 ? trackBg.width : Math.max(1, width - 8)
        if (e <= s || w <= 0)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    function xToTimestamp(x) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var w = trackBg.width > 0 ? trackBg.width : Math.max(1, width - 8)
        var ratio = Math.max(0, Math.min(1, x / Math.max(1, w)))
        return (s + ratio * (e - s)) * 1000
    }

    function formatFull(tsMs) {
        if (tsMs <= 0)
            return ""
        return Qt.formatDateTime(new Date(tsMs), "ddd MMM dd  hh:mm:ss")
    }

    function visibleMotionCount() {
        var n = 0
        if (!motionPoints)
            return 0
        for (var i = 0; i < motionPoints.length; ++i) {
            var p = motionPoints[i]
            var m = Number(p.motion !== undefined ? p.motion : 0)
            if (m >= minMotion)
                n++
        }
        return n
    }

    Rectangle {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: collapsed ? 0 : 32
        color: "#161616"
        visible: !collapsed
        z: 20

        Text {
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
                       + "  -  "
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
        height: 40
        color: "#1A1A1A"
        radius: 3
        visible: !collapsed
        border.color: "#333"
        border.width: 1
        z: 5
        clip: true

        TimelineSegments {
            anchors.fill: parent
            recordings: timeline.recordings
            startTs: timeline.effectiveStartTs()
            endTs: timeline.effectiveEndTs()
            zoom: 1.0
            pan: 0
            timelineWidth: trackBg.width
            timestampToX: timeline.timestampToX
            z: 1
        }

        // MOTION TICKS (filtered by minMotion)
        Repeater {
            model: timeline.motionPoints
            z: 5

            Rectangle {
                property real sec: {
                    var t = 0
                    if (typeof start !== "undefined" && start)
                        t = Number(start)
                    else if (modelData)
                        t = Number(modelData.start || modelData.start_time || 0)
                    if (t > 100000000000)
                        t = t / 1000
                    return t
                }
                property real mot: {
                    if (typeof motion !== "undefined" && motion)
                        return Number(motion)
                    if (modelData)
                        return Number(modelData.motion || 0)
                    return 0
                }

                width: 3
                height: Math.min(parent.height - 4, 14 + Math.min(22, mot / 8.0))
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                color: "#FF6D00"
                opacity: 1.0
                x: timeline.timestampToX(sec * 1000) - 1
                visible: sec > 0 && mot >= timeline.minMotion
            }
        }

        // Event ticks
        Repeater {
            model: timeline.events
            z: 6

            Rectangle {
                property real sec: {
                    var t = 0
                    if (typeof start !== "undefined" && start)
                        t = Number(start)
                    else if (modelData)
                        t = Number(modelData.start || 0)
                    if (t > 100000000000)
                        t = t / 1000
                    return t
                }

                width: 3
                height: 18
                y: 2
                radius: 1
                color: "#FFC107"
                x: timeline.timestampToX(sec * 1000) - 1
                visible: sec > 0
            }
        }
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
            return recordings.length + " rec, "
                 + visibleMotionCount() + "/" + motionPoints.length + " motion (min " + minMotion + "), "
                 + events.length + " events — green=record, orange=motion"
        }
        color: "#777777"
        font.pixelSize: 10
        visible: !collapsed
        z: 5
    }
}