import QtQuick 2.15
import "qrc:/app/resources/qml/components"
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: trackBg
    height: 40
    color: NxStyle.panelAlt
    radius: NxStyle.smallRadius
    border.color: NxStyle.border
    border.width: 1
    clip: true

    property var timeline: null
    property real minMotion: 15

    signal seekRequested(real tsMs)
    signal hoverTimeChanged(real tsMs)

    property bool panActive: false

    // Cached view — updated from timeline, not via function bindings
    property real viewStart: timeline && timeline.viewStartTs > 0 ? timeline.viewStartTs : 0
    property real viewEnd: timeline && timeline.viewEndTs > timeline.viewStartTs ? timeline.viewEndTs : 1
    property real contentWidth: Math.max(1, width)

    function mapX(tsMs) {
        var s = viewStart
        var e = viewEnd
        var w = contentWidth
        if (e <= s)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    onViewStartChanged: ticks.requestPaint()
    onViewEndChanged: ticks.requestPaint()
    onContentWidthChanged: ticks.requestPaint()

    Connections {
        target: timeline
        function onMotionPointsChanged() { ticks.requestPaint() }
        function onEventsChanged() { ticks.requestPaint() }
        function onViewStartTsChanged() { ticks.requestPaint() }
        function onViewEndTsChanged() { ticks.requestPaint() }
        function onPlayheadTsMsChanged() { ticks.requestPaint() }
        function onExportStartMsChanged() { ticks.requestPaint() }
        function onExportEndMsChanged() { ticks.requestPaint() }
        function onIsPlaybackChanged() { ticks.requestPaint() }
    }

    TimelineSegments {
        anchors.fill: parent
        recordings: timeline ? timeline.recordings : []
        timeline: trackBg.timeline
        viewStart: trackBg.viewStart
        viewEnd: trackBg.viewEnd
        contentWidth: trackBg.contentWidth
        z: 1
    }

    // Single canvas instead of hundreds/thousands of Repeater bindings
    Canvas {
        id: ticks
        anchors.fill: parent
        z: 5
        antialiasing: false

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!timeline)
                return

            var h = height
            var w = width
            var s = trackBg.viewStart
            var e = trackBg.viewEnd
            if (e <= s)
                return

            function xOf(tsMs) {
                var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
                return Math.max(0, Math.min(w, ratio * w))
            }

            // Motion
            var pts = timeline.motionPoints || []
            var minM = trackBg.minMotion
            ctx.fillStyle = NxStyle.motion
            for (var i = 0; i < pts.length; ++i) {
                var p = pts[i]
                var mot = Number(p.motion || 0)
                if (mot < minM)
                    continue
                var t = Number(p.start || p.start_time || 0)
                if (t > 100000000000)
                    t = t / 1000
                if (t < s || t > e)
                    continue
                var mh = Math.min(h - 4, 14 + Math.min(22, mot / 8.0))
                var mx = xOf(t * 1000)
                ctx.fillRect(mx - 1, h - 2 - mh, 3, mh)
            }

            // Events
            var evs = timeline.events || []
            ctx.fillStyle = NxStyle.event
            for (var j = 0; j < evs.length; ++j) {
                var et = Number(evs[j].start || 0)
                if (et > 100000000000)
                    et = et / 1000
                if (et < s || et > e)
                    continue
                var ex = xOf(et * 1000)
                ctx.fillRect(ex - 1, 2, 3, 18)
            }

            // Export range
            if (timeline.exportStartMs > 0 && timeline.exportEndMs > timeline.exportStartMs) {
                var x1 = xOf(timeline.exportStartMs)
                var x2 = xOf(timeline.exportEndMs)
                ctx.fillStyle = "rgba(58,106,255,0.33)"
                ctx.fillRect(x1, 0, Math.max(2, x2 - x1), h)
                ctx.strokeStyle = "#6A8AFF"
                ctx.strokeRect(x1, 0, Math.max(2, x2 - x1), h)
            }

            // Playhead
            if (timeline.playheadTsMs > 0) {
                var px = xOf(timeline.playheadTsMs)
                ctx.fillStyle = timeline.isPlayback ? NxStyle.text : NxStyle.playhead
                ctx.fillRect(px - 1.5, 0, 3, h)
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            if (!timeline)
                return
            var factor = event.angleDelta.y > 0 ? 1.25 : 0.8
            timeline.zoomAt(event.x, factor)
            event.accepted = true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        z: 50

        property real pressX: 0
        property real lastX: 0
        property bool dragging: false
        property bool panning: false
        property real dragThreshold: 6

        onPositionChanged: function(event) {
            if (!timeline)
                return

            var ts = timeline.xToTimestamp(event.x)
            trackBg.hoverTimeChanged(ts)

            if (!(event.buttons & Qt.LeftButton))
                return

            var dx = event.x - pressX

            if (event.modifiers & Qt.ShiftModifier) {
                panning = true
                dragging = false
                trackBg.panActive = true
                var step = event.x - lastX
                lastX = event.x
                if (Math.abs(step) > 0.5)
                    timeline.panByPixels(step)
                return
            }

            if (!dragging && Math.abs(dx) >= dragThreshold) {
                dragging = true
                var startTs = timeline.xToTimestamp(pressX)
                timeline.exportStartMs = startTs
                timeline.exportEndMs = startTs
            }

            if (dragging)
                timeline.exportEndMs = timeline.xToTimestamp(event.x)
        }

        onPressed: function(event) {
            pressX = event.x
            lastX = event.x
            dragging = false
            panning = false
            trackBg.panActive = false
        }

        onReleased: function(event) {
            if (!timeline) {
                dragging = false
                panning = false
                trackBg.panActive = false
                return
            }

            if (panning) {
                panning = false
                trackBg.panActive = false
                return
            }

            if (dragging) {
                if (timeline.exportEndMs < timeline.exportStartMs) {
                    var tmp = timeline.exportStartMs
                    timeline.exportStartMs = timeline.exportEndMs
                    timeline.exportEndMs = tmp
                }
                if (timeline.exportEndMs - timeline.exportStartMs < 2000) {
                    timeline.exportStartMs = -1
                    timeline.exportEndMs = -1
                }
                dragging = false
                return
            }

            var ts = timeline.xToTimestamp(event.x)
            if (ts > 0)
                trackBg.seekRequested(ts)
        }

        onExited: trackBg.hoverTimeChanged(-1)

        onDoubleClicked: {
            if (timeline)
                timeline.resetZoom()
        }
    }
}