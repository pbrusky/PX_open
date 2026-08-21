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

    property real dataStartTs: 0
    property real dataEndTs: 0
    property real viewStartTs: 0
    property real viewEndTs: 0
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
        calendarPopup.visible = false
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
        var minT = dataStartBound(), maxT = dataEndBound(), first = true
        for (var i = 0; i < motionPoints.length; ++i) {
            var p = motionPoints[i]
            var t = normalizeSec(p.start !== undefined ? p.start : p.start_time)
            if (t <= 0)
                continue
            if (first) {
                minT = t; maxT = t; first = false
            } else {
                if (t < minT) minT = t
                if (t > maxT) maxT = t
            }
        }
        if (!first)
            setDataRange(minT, maxT)
    }
    function clampView() {
        var ds = dataStartBound(), de = dataEndBound()
        var span = viewEndTs - viewStartTs
        if (span < minViewSpan) span = minViewSpan
        if (span > maxViewSpan) span = maxViewSpan
        if (span > de - ds && de > ds) span = de - ds
        if (viewStartTs < ds) viewStartTs = ds
        if (viewStartTs + span > de) {
            viewStartTs = de - span
            if (viewStartTs < ds) viewStartTs = ds
        }
        viewEndTs = viewStartTs + span
        if (viewEndTs > de) viewEndTs = de
        if (viewEndTs <= viewStartTs)
            viewEndTs = viewStartTs + minViewSpan
    }
    function effectiveStartTs() {
        if (viewEndTs > viewStartTs) return viewStartTs
        return dataStartBound()
    }
    function effectiveEndTs() {
        if (viewEndTs > viewStartTs) return viewEndTs
        return dataEndBound()
    }
    function zoomAt(cursorX, factor) {
        var s = effectiveStartTs(), e = effectiveEndTs()
        var w = track.width > 0 ? track.width : 1
        var ratio = Math.max(0, Math.min(1, cursorX / w))
        var center = s + ratio * (e - s)
        var span = (e - s) / factor
        if (span < minViewSpan) span = minViewSpan
        if (span > maxViewSpan) span = maxViewSpan
        viewStartTs = center - span * ratio
        viewEndTs = viewStartTs + span
        clampView()
    }
    function panByPixels(dx) {
        var s = effectiveStartTs(), e = effectiveEndTs()
        var w = track.width > 0 ? track.width : 1
        var span = e - s
        viewStartTs += -(dx / w) * span
        viewEndTs += -(dx / w) * span
        clampView()
    }
    function resetZoom() {
        viewStartTs = dataStartBound()
        viewEndTs = dataEndBound()
        clampView()
    }
    function timestampToX(tsMs) {
        var s = effectiveStartTs(), e = effectiveEndTs()
        var w = track.width > 0 ? track.width : Math.max(1, width - 8)
        if (e <= s || w <= 0) return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }
    function xToTimestamp(x) {
        var s = effectiveStartTs(), e = effectiveEndTs()
        var w = track.width > 0 ? track.width : Math.max(1, width - 8)
        var ratio = Math.max(0, Math.min(1, x / Math.max(1, w)))
        return (s + ratio * (e - s)) * 1000
    }
    function formatFull(tsMs) {
        if (tsMs <= 0) return ""
        return Qt.formatDateTime(new Date(tsMs), "ddd MMM dd  hh:mm:ss")
    }
    function visibleMotionCount() {
        var n = 0
        if (!motionPoints) return 0
        for (var i = 0; i < motionPoints.length; ++i) {
            if (Number(motionPoints[i].motion || 0) >= minMotion)
                n++
        }
        return n
    }
    function viewSpanLabel() {
        var span = effectiveEndTs() - effectiveStartTs()
        if (span < 90) return Math.round(span) + "s"
        if (span < 3600) return Math.round(span / 60) + "m"
        if (span < 86400) return (span / 3600).toFixed(1) + "h"
        return (span / 86400).toFixed(1) + "d"
    }
    function dayHasRecording(y, m, d) {
        var dayStart = new Date(y, m - 1, d, 0, 0, 0).getTime() / 1000
        var dayEnd = dayStart + 86400
        if (!recordings) return false
        for (var i = 0; i < recordings.length; ++i) {
            var s = normalizeSec(recordings[i].start)
            var e = normalizeSec(recordings[i].end)
            if (e > dayStart && s < dayEnd) return true
        }
        return false
    }
    function jumpToDay(y, m, d) {
        var dayStart = new Date(y, m - 1, d, 0, 0, 0).getTime() / 1000
        var dayEnd = dayStart + 86400
        if (dayStart < dataStartBound()) dataStartTs = dayStart
        if (dayEnd > dataEndBound()) dataEndTs = dayEnd
        viewStartTs = dayStart
        viewEndTs = dayEnd
        clampView()
        calendarPopup.visible = false
        if (dayHasRecording(y, m, d)) {
            seekRequested(dayStart * 1000)
            playbackPositionMs = dayStart * 1000
        }
    }

    TimelineStatusBar {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: !collapsed
        z: 20
        timeline: timeline
        calendarOpen: calendarPopup.visible
        onCalendarToggled: {
            if (!calendarPopup.visible) {
                var d = new Date(effectiveStartTs() * 1000)
                calendarPopup.calYear = d.getFullYear()
                calendarPopup.calMonth = d.getMonth() + 1
            }
            calendarPopup.visible = !calendarPopup.visible
        }
        onZoomOut: zoomAt(track.width / 2, 0.7)
        onZoomIn: zoomAt(track.width / 2, 1.4)
        onResetZoom: resetZoom()
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

    TimelineTrack {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.top: ruler.bottom
        anchors.topMargin: 6
        visible: !collapsed
        z: 5
        timeline: timeline
        minMotion: timeline.minMotion
        onSeekRequested: function(tsMs) {
            timeline.playbackPositionMs = tsMs
            timeline.seekRequested(tsMs)
        }
        onHoverTimeChanged: function(tsMs) {
            timeline.hoverTsMs = tsMs
            cursorLine.visible = tsMs > 0
            if (tsMs > 0)
                cursorLine.x = track.x + timeline.timestampToX(tsMs) - 1
        }
    }

    Item {
        id: playheadItem
        width: 18
        height: track.height + 22
        anchors.top: track.top
        anchors.topMargin: -14
        x: track.x + timestampToX(playheadTsMs) - width / 2
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

    Rectangle {
        id: cursorLine
        width: 2
        anchors.top: track.top
        anchors.bottom: track.bottom
        color: "#FFC107"
        opacity: 0.9
        visible: false
        z: 40
    }

    TimelineCalendarPopup {
        id: calendarPopup
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        z: 200
        timeline: timeline
        onDaySelected: function(y, m, d) {
            jumpToDay(y, m, d)
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
                 + events.length + " events — wheel=zoom, Shift+drag=pan"
        }
        color: "#777777"
        font.pixelSize: 10
        visible: !collapsed
        z: 5
    }
}