import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent ? parent.width : 800

    property bool collapsed: true
    property bool allowAutoReveal: false
    property bool pointerInside: false

    property real minMotion: 15

    // Full data range (from Frigate recordings/motion)
    property real dataStartTs: 0
    property real dataEndTs: 0

    // Visible window (zoom/pan) — seconds since epoch
    property real viewStartTs: 0
    property real viewEndTs: 0

    // Min/max visible span (seconds): 30s … 7 days
    readonly property real minViewSpan: 30
    readonly property real maxViewSpan: 7 * 24 * 3600

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
    property real playbackPositionMs: 0
    property real startTs: 0
    property real endTs: 0
    property bool isPlayback: false
    property real hoverTsMs: -1

    property real currentTimeMs: Date.now()
    readonly property real playheadTsMs: {
        if (isPlayback && playbackPositionMs > 0)
            return playbackPositionMs
        return currentTimeMs
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: currentTimeMs = Date.now()
    }

    Timer {
        interval: 250
        running: !collapsed && isPlayback && playbackPositionMs > 0
        repeat: true
        onTriggered: {
            var next = playbackPositionMs + interval
            var endMs = dataEndBound() * 1000
            if (endMs > 0 && next > endMs)
                next = endMs
            playbackPositionMs = next
        }
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
                setDataRange(startTs, endTs)
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

    function dataStartBound() {
        if (dataStartTs > 0)
            return dataStartTs
        if (endTs > startTs)
            return startTs
        return Date.now() / 1000 - 3600
    }

    function dataEndBound() {
        if (dataEndTs > dataStartTs)
            return dataEndTs
        if (endTs > startTs)
            return endTs
        return Date.now() / 1000
    }

    function setDataRange(s, e) {
        s = normalizeSec(s)
        e = normalizeSec(e)
        if (e <= s)
            return
        if (dataStartTs <= 0 || s < dataStartTs)
            dataStartTs = s
        if (e > dataEndTs)
            dataEndTs = e
        // First time: fit full range
        if (viewEndTs <= viewStartTs) {
            viewStartTs = dataStartTs
            viewEndTs = dataEndTs
        }
        clampView()
    }

    function applyMotionPoints(points) {
        motionPoints = points || []
        if (!motionPoints || motionPoints.length === 0)
            return

        var minT = dataStartBound()
        var maxT = dataEndBound()
        var first = true
        for (var i = 0; i < motionPoints.length; ++i) {
            var p = motionPoints[i]
            var t = normalizeSec(p.start !== undefined ? p.start : p.start_time)
            if (t <= 0)
                continue
            if (first) {
                minT = t
                maxT = t
                first = false
            } else {
                if (t < minT) minT = t
                if (t > maxT) maxT = t
            }
        }
        if (!first)
            setDataRange(minT, maxT)
    }

    function clampView() {
        var ds = dataStartBound()
        var de = dataEndBound()
        var span = viewEndTs - viewStartTs
        if (span < minViewSpan)
            span = minViewSpan
        if (span > maxViewSpan)
            span = maxViewSpan
        if (span > de - ds && de > ds)
            span = de - ds

        if (viewStartTs < ds)
            viewStartTs = ds
        if (viewStartTs + span > de) {
            viewStartTs = de - span
            if (viewStartTs < ds)
                viewStartTs = ds
        }
        viewEndTs = viewStartTs + span
        if (viewEndTs > de)
            viewEndTs = de
        if (viewEndTs <= viewStartTs)
            viewEndTs = viewStartTs + minViewSpan
    }

    function effectiveStartTs() {
        if (viewEndTs > viewStartTs)
            return viewStartTs
        return dataStartBound()
    }

    function effectiveEndTs() {
        if (viewEndTs > viewStartTs)
            return viewEndTs
        return dataEndBound()
    }

    // Zoom centered on time under cursor (cursorX relative to trackBg)
    function zoomAt(cursorX, factor) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var w = trackBg.width > 0 ? trackBg.width : 1
        var ratio = Math.max(0, Math.min(1, cursorX / w))
        var center = s + ratio * (e - s)
        var span = (e - s) / factor
        if (span < minViewSpan)
            span = minViewSpan
        if (span > maxViewSpan)
            span = maxViewSpan
        viewStartTs = center - span * ratio
        viewEndTs = viewStartTs + span
        clampView()
    }

    function panByPixels(dx) {
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var w = trackBg.width > 0 ? trackBg.width : 1
        var span = e - s
        var dt = -(dx / w) * span
        viewStartTs += dt
        viewEndTs += dt
        clampView()
    }

    function resetZoom() {
        viewStartTs = dataStartBound()
        viewEndTs = dataEndBound()
        clampView()
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

    function viewSpanLabel() {
        var span = effectiveEndTs() - effectiveStartTs()
        if (span < 90)
            return Math.round(span) + "s"
        if (span < 3600)
            return Math.round(span / 60) + "m"
        if (span < 86400)
            return (span / 3600).toFixed(1) + "h"
        return (span / 86400).toFixed(1) + "d"
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

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var s = effectiveStartTs()
                    var e = effectiveEndTs()
                    return Qt.formatDateTime(new Date(s * 1000), "hh:mm:ss")
                           + "  -  "
                           + Qt.formatDateTime(new Date(e * 1000), "hh:mm:ss")
                           + "  (" + viewSpanLabel() + ")"
                }
                color: "#888888"
                font.pixelSize: 12
            }

            // Zoom controls
            Rectangle {
                width: 28
                height: 22
                radius: 3
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: "−"
                    color: "white"
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: zoomAt(trackBg.width / 2, 0.7)
                }
            }
            Rectangle {
                width: 28
                height: 22
                radius: 3
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: zoomAt(trackBg.width / 2, 1.4)
                }
            }
            Rectangle {
                width: 44
                height: 22
                radius: 3
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: "1:1"
                    color: "white"
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: resetZoom()
                }
            }
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
                        && sec >= timeline.effectiveStartTs()
                        && sec <= timeline.effectiveEndTs()
            }
        }

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
                        && sec >= timeline.effectiveStartTs()
                        && sec <= timeline.effectiveEndTs()
            }
        }

        Rectangle {
            id: trackPlayhead
            width: 3
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: timeline.timestampToX(timeline.playheadTsMs) - width / 2
            color: timeline.isPlayback ? "#FFFFFF" : "#90CAF9"
            border.color: "#000000"
            border.width: 1
            visible: timeline.playheadTsMs > 0
            z: 80
        }

        // Wheel zoom (NX-style)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                var factor = event.angleDelta.y > 0 ? 1.25 : 0.8
                zoomAt(event.x, factor)
                event.accepted = true
            }
        }

        // Shift+drag to pan
        DragHandler {
            id: panHandler
            acceptedButtons: Qt.LeftButton
            acceptedModifiers: Qt.ShiftModifier
            target: null
            property real lastX: 0
            onActiveChanged: {
                if (active)
                    lastX = centroid.position.x
            }
            onTranslationChanged: {
                if (!active)
                    return
                var dx = centroid.position.x - lastX
                lastX = centroid.position.x
                if (Math.abs(dx) > 0.5)
                    panByPixels(dx)
            }
        }

        // Double-click → fit full range
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: resetZoom()
        }
    }

    Item {
        id: playheadItem
        width: 18
        height: trackBg.height + 22
        anchors.top: trackBg.top
        anchors.topMargin: -14
        x: trackBg.x + timestampToX(playheadTsMs) - width / 2
        visible: !collapsed && playheadTsMs > 0
        z: 80

        Rectangle {
            width: 3
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            color: isPlayback ? "#FFFFFF" : "#90CAF9"
        }

        Rectangle {
            width: 12
            height: 8
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            color: isPlayback ? "#FFFFFF" : "#90CAF9"
            border.color: "#000000"
            border.width: 1
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
        enabled: !collapsed && !panHandler.active

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
                 + visibleMotionCount() + "/" + motionPoints.length + " motion, "
                 + events.length + " events — wheel=zoom, Shift+drag=pan, dbl-click=reset"
        }
        color: "#777777"
        font.pixelSize: 10
        visible: !collapsed
        z: 5
    }
}