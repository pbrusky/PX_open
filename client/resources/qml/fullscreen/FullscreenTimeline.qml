import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs
import "qrc:/app/resources/qml/components"
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: timeline
    width: parent ? parent.width : 800

    property bool collapsed: true
    property bool allowAutoReveal: false
    property bool pointerInside: false
    property bool calendarOpen: false
    property bool timelineLoading: false
    property bool refreshing: false
    property real minMotion: 15

    property real dataStartTs: 0
    property real dataEndTs: 0
    property real viewStartTs: 0
    property real viewEndTs: 0
    readonly property real minViewSpan: 30
    readonly property real maxViewSpan: 7 * 24 * 3600
    readonly property real defaultViewSpan: 24 * 3600

    property bool _viewLock: false
    property bool _fixedDayMode: false
    property bool _lastHoverActive: false
    property bool _hoverEmitPending: false
    property bool _pendingHoverValue: false
    property bool _activated: false
    property bool _backendDrivesPlayhead: false
    property bool followLive: true
    readonly property int maxMotionPoints: 800

    signal seekRequested(real timestampMs)
    signal hoverActiveChanged(bool active)
    signal refreshRequested()

    property real exportStartMs: -1
    property real exportEndMs: -1
    property bool exportBusy: false
    property real exportPercent: 0
    property string exportStatusMessage: ""
    property real _lastProgressUiAt: 0
    property real exportBytesReceived: 0
    property real exportBytesPerSec: 0
    property real exportEtaSec: -1
    property real _progressSampleBytes: 0
    property real _progressSampleAt: 0
    property bool exportUiOpen: false

    function isExportUiOpen() {
        if (exportBusy)
            return true
        if (exportEndMs > exportStartMs)
            return true
        if (exportConfirmLoader.item && exportConfirmLoader.item.visible)
            return true
        return false
    }

    function refreshExportUiOpen() {
        exportUiOpen = isExportUiOpen()
    }

    function activate() {
        if (_activated)
            return
        _activated = true
    }

    function emitHover(active) {
        active = !!active
        if (active === _lastHoverActive && !_hoverEmitPending)
            return
        _lastHoverActive = active
        _pendingHoverValue = active
        if (_hoverEmitPending)
            return
        _hoverEmitPending = true
        Qt.callLater(function() {
            _hoverEmitPending = false
            hoverActiveChanged(_pendingHoverValue)
        })
    }

    function showTimeline() {
        if (!allowAutoReveal)
            return
        activate()
        collapsed = false
    }

    function hideTimeline() {
        if (isExportUiOpen())
            return
        collapsed = true
        hoverTsMs = -1
        pointerInside = false
        if (calendarPopup.visible)
            calendarPopup.visible = false
        calendarOpen = false
        if (exportConfirmLoader.item && exportConfirmLoader.item.visible)
            exportConfirmLoader.item.close()
        refreshExportUiOpen()
        emitHover(false)
    }

    height: collapsed ? 4 : 150
    visible: true
    color: collapsed ? "#00000000" : NxStyle.panel
    border.color: collapsed ? "transparent" : NxStyle.border
    border.width: collapsed ? 0 : 1
    radius: collapsed ? 0 : NxStyle.radius
    z: 10
    clip: false

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var recordings: []
    property var events: []
    property var motionPoints: []
    property var recordingDays: []
    property real playbackPositionMs: 0
    property real startTs: 0
    property real endTs: 0
    property bool isPlayback: false
    property real hoverTsMs: -1
    property real currentTimeMs: Date.now()
    property real playheadTsMs: 0

    property alias exportConfirm: exportConfirmLoader

    function updatePlayhead() {
        var next = (isPlayback && playbackPositionMs > 0) ? playbackPositionMs : currentTimeMs
        if (Math.abs(next - playheadTsMs) < 1)
            return
        playheadTsMs = next
    }

    function followCurrentTime() {
        if (!followLive || isPlayback || _fixedDayMode || _viewLock)
            return
        if (!(viewEndTs > viewStartTs))
            return

        var nowSec = Date.now() / 1000
        var de = dataEndBound()
        if (dataEndTs > dataStartTs && de < nowSec) {
            dataEndTs = nowSec
            de = nowSec
        }
        if (de < nowSec)
            return

        var span = viewEndTs - viewStartTs
        if (!(span > 0) || span > maxViewSpan)
            span = Math.min(defaultViewSpan, de - dataStartBound())
        if (span < minViewSpan)
            span = minViewSpan
        if (span > maxViewSpan)
            span = maxViewSpan

        var ds = dataStartBound()
        var end = Math.min(de, nowSec)
        var start = end - span
        if (start < ds)
            start = ds
        if (end - start < minViewSpan) {
            start = Math.max(ds, end - minViewSpan)
            end = start + minViewSpan
            if (end > de)
                end = de
        }
        if (!(end > start))
            return

        _viewLock = true
        if (Math.abs(viewStartTs - start) > 0.05)
            viewStartTs = start
        if (Math.abs(viewEndTs - end) > 0.05)
            viewEndTs = end
        _viewLock = false
    }

    function exportSpanLabel() {
        if (!(exportEndMs > exportStartMs))
            return ""
        var sec = (exportEndMs - exportStartMs) / 1000
        if (sec < 90)
            return Math.round(sec) + "s"
        if (sec < 3600)
            return Math.round(sec / 60) + "m"
        return (sec / 3600).toFixed(1) + "h"
    }

    function clearExportRange() {
        exportStartMs = -1
        exportEndMs = -1
        refreshExportUiOpen()
    }

    function requestRecordingsRefresh() {
        if (!frigateRef)
            return
        var id = (cameraId && cameraId.length) ? cameraId : cameraName
        if (!id || !id.length)
            return
        timelineLoading = true
        refreshing = true
        var nowSec = Math.floor(Date.now() / 1000)
        if (typeof frigateRef.loadRecordingsRange === "function")
            frigateRef.loadRecordingsRange(id, nowSec - 6 * 3600, nowSec)
        else if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)
    }

    function cancelExport() {
        if (!exportBusy)
            return
        exportStallTimer.stop()
        if (frigateRef && typeof frigateRef.cancelExport === "function")
            frigateRef.cancelExport()
    }

    function defaultExportFileName() {
        var cam = (cameraName || cameraId || "camera").toString().replace(/[^\w\-]+/g, "_")
        var a = new Date(exportStartMs)
        var b = new Date(exportEndMs)
        function pad(n) { return (n < 10 ? "0" : "") + n }
        return cam + "_"
             + a.getFullYear() + "-" + pad(a.getMonth() + 1) + "-" + pad(a.getDate())
             + "_" + pad(a.getHours()) + "-" + pad(a.getMinutes())
             + "_to_" + pad(b.getHours()) + "-" + pad(b.getMinutes())
             + ".mp4"
    }

    function requestExport() {
        if (!(exportEndMs > exportStartMs) || !frigateRef)
            return
        if (typeof frigateRef.exportClip !== "function")
            return
        activate()
        allowAutoReveal = true
        collapsed = false
        emitHover(true)
        exportConfirmLoader.active = true
        Qt.callLater(function() {
            if (!exportConfirmLoader.item)
                return
            var cam = cameraName !== "" ? cameraName : cameraId
            exportConfirmLoader.item.openWith(cam, exportStartMs, exportEndMs)
            refreshExportUiOpen()
        })
    }

    function startExportDownload(sMs, eMs) {
        exportStartMs = sMs
        exportEndMs = eMs
        activate()
        allowAutoReveal = true
        collapsed = false
        refreshExportUiOpen()
        exportFileDialog.selectedFile = "file:///" + defaultExportFileName()
        exportFileDialog.open()
    }

    Timer {
        interval: 1000
        running: _activated
        repeat: true
        onTriggered: {
            currentTimeMs = Date.now()
            if (!isPlayback) {
                updatePlayhead()
                followCurrentTime()
            }
        }
    }

    Timer {
        interval: 250
        running: _activated && !collapsed && isPlayback && playbackPositionMs > 0 && !_backendDrivesPlayhead
        repeat: true
        onTriggered: {
            var next = playbackPositionMs + interval
            var endMs = dataEndBound() * 1000
            if (endMs > 0 && next > endMs)
                next = endMs
            if (Math.abs(next - playbackPositionMs) > 1) {
                playbackPositionMs = next
                updatePlayhead()
            }
        }
    }

    // Safety net: a superseded or failed day request can leave the loading
    // banner up indefinitely. Always clear it after a bounded wait.
    Timer {
        id: dayLoadWatchdog
        interval: 20000
        repeat: false
        onTriggered: {
            if (timelineLoading) {
                timelineLoading = false
                refreshing = false
            }
        }
    }

    Timer {
        id: exportDoneClearTimer
        interval: 1800
        onTriggered: {
            exportPercent = 0
            exportStatusMessage = ""
            exportBytesReceived = 0
            exportBytesPerSec = 0
            exportEtaSec = -1
            exportBusy = false
            refreshExportUiOpen()
        }
    }

    Timer {
        id: exportStallTimer
        interval: 4000
        repeat: false
        onTriggered: {
            if (!exportBusy)
                return
            if (exportBytesReceived > 0) {
                exportBusy = false
                exportPercent = 100
                exportBytesPerSec = 0
                exportEtaSec = -1
                exportStatusMessage = "Saved"
                clearExportRange()
                exportDoneClearTimer.restart()
            }
        }
    }

    HoverHandler {
        enabled: !timeline.collapsed
        onHoveredChanged: {
            if (timeline.collapsed)
                return
            pointerInside = hovered
            emitHover(hovered || timeline.isExportUiOpen())
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
            timelineLoading = false
            recordings = segments || []
            if (recordings.length > 0) {
                startTs = Number(recordings[0].start)
                endTs = Number(recordings[recordings.length - 1].end)
                if (!_fixedDayMode)
                    setDataRange(startTs, endTs)
                else
                    clampView()
            } else {
                // Don't leave stale bounds behind when a camera has no data.
                startTs = 0
                endTs = 0
                dataStartTs = 0
                dataEndTs = 0
                applyDefaultView()
            }
        }

        function onRecordingsRefreshFinished(id) {
            if (id !== cameraId && id !== cameraName)
                return
            dayLoadWatchdog.stop()
            timelineLoading = false
            refreshing = false
        }

        function onEventsLoaded(id, list) {
            if (id !== cameraId && id !== cameraName)
                return
            events = list || []
        }

        function onMotionActivityLoaded(id, points) {
            if (id !== cameraId && id !== cameraName)
                return
            applyMotionPoints(points)
        }

        function onRecordingDaysLoaded(id, days) {
            if (id !== cameraId && id !== cameraName)
                return
            recordingDays = days || []
        }

        function onPlaybackPositionChanged(id, posMs) {
            if (id !== cameraId && id !== cameraName)
                return
            _backendDrivesPlayhead = false
            if (Math.abs(posMs - playbackPositionMs) > 1) {
                playbackPositionMs = posMs
                updatePlayhead()
            }
        }

        function onExportProgress(received, total) {
            if (!exportBusy)
                exportBusy = true

            var now = Date.now()
            var grew = received > exportBytesReceived
            exportBytesReceived = received

            if (timeline._progressSampleAt > 0) {
                var dt = (now - timeline._progressSampleAt) / 1000.0
                if (dt > 0.25) {
                    var db = received - timeline._progressSampleBytes
                    if (db >= 0)
                        exportBytesPerSec = db / dt
                    timeline._progressSampleBytes = received
                    timeline._progressSampleAt = now
                }
            } else {
                timeline._progressSampleBytes = received
                timeline._progressSampleAt = now
            }

            if (grew)
                exportStallTimer.restart()

            if (timeline._lastProgressUiAt && (now - timeline._lastProgressUiAt) < 250)
                return
            timeline._lastProgressUiAt = now

            var mb = received / (1024 * 1024)
            var sizeStr = mb < 0.1
                ? (Math.round(received / 1024) + " KB")
                : (mb.toFixed(1) + " MB")

            var rateStr = ""
            if (exportBytesPerSec > 1024)
                rateStr = "  ·  " + (exportBytesPerSec / (1024 * 1024)).toFixed(1) + " MB/s"

            if (total > 0) {
                exportPercent = Math.min(99.5, (received * 100.0) / total)
                if (exportBytesPerSec > 1024)
                    exportEtaSec = Math.max(0, total - received) / exportBytesPerSec
                else
                    exportEtaSec = -1
                exportStatusMessage = sizeStr + rateStr
            } else {
                exportPercent = -1
                exportEtaSec = -1
                exportStatusMessage = sizeStr + rateStr
            }
            refreshExportUiOpen()
        }

        function onExportFinished(ok, message, path) {
            exportStallTimer.stop()
            exportBusy = false
            exportPercent = ok ? 100 : 0
            exportBytesPerSec = 0
            exportEtaSec = -1
            exportStatusMessage = message || (ok ? "Saved" : "Failed")
            var msg = (message || "").toLowerCase()
            if (ok || msg.indexOf("cancel") >= 0)
                clearExportRange()
            exportDoneClearTimer.restart()
            refreshExportUiOpen()
        }
    }

    onIsPlaybackChanged: {
        if (!isPlayback) {
            _backendDrivesPlayhead = false
            followLive = true
            updatePlayhead()
        } else {
            followLive = false
            activate()
        }
    }

    onCollapsedChanged: {
        if (!collapsed)
            activate()
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
        return Date.now() / 1000 - defaultViewSpan
    }

    function dataEndBound() {
        if (dataEndTs > dataStartTs)
            return dataEndTs
        if (endTs > startTs)
            return endTs
        return Date.now() / 1000
    }

    function applyDefaultView() {
        if (_viewLock)
            return
        _viewLock = true

        var nowSec = Date.now() / 1000
        var de = dataEndBound()
        var ds = dataStartBound()
        var end = Math.min(de, nowSec)
        var start = end - defaultViewSpan
        if (start < ds)
            start = ds

        if (Math.abs(viewStartTs - start) > 0.1)
            viewStartTs = start
        if (Math.abs(viewEndTs - end) > 0.1)
            viewEndTs = end

        if (viewEndTs <= viewStartTs)
            viewEndTs = viewStartTs + minViewSpan

        _viewLock = false
    }

    function clampView() {
        if (_viewLock)
            return
        _viewLock = true

        var ds = dataStartBound()
        var de = dataEndBound()
        if (!(de > ds)) {
            _viewLock = false
            return
        }

        var span = viewEndTs - viewStartTs
        if (!(span > 0) || span < minViewSpan)
            span = Math.min(defaultViewSpan, de - ds)
        if (span < minViewSpan)
            span = minViewSpan
        if (span > maxViewSpan)
            span = maxViewSpan
        if (span > de - ds)
            span = de - ds

        var ns = viewStartTs
        if (ns < ds)
            ns = ds
        if (ns + span > de)
            ns = de - span
        if (ns < ds)
            ns = ds

        var ne = ns + span
        if (ne > de)
            ne = de
        if (ne <= ns)
            ne = ns + minViewSpan

        if (Math.abs(ns - viewStartTs) > 0.05)
            viewStartTs = ns
        if (Math.abs(ne - viewEndTs) > 0.05)
            viewEndTs = ne

        _viewLock = false
    }

    function setDataRange(s, e) {
        if (_viewLock)
            return

        s = normalizeSec(s)
        e = normalizeSec(e)
        if (!(e > s))
            return

        if (_fixedDayMode) {
            clampView()
            return
        }

        var changed = false
        if (dataStartTs <= 0 || s < dataStartTs) {
            dataStartTs = s
            changed = true
        }
        if (e > dataEndTs) {
            dataEndTs = e
            changed = true
        }

        if (viewEndTs <= viewStartTs)
            applyDefaultView()
        else if (changed)
            clampView()
    }

    function applyMotionPoints(points) {
        points = points || []
        if (points.length <= maxMotionPoints) {
            motionPoints = points
            return
        }
        var step = points.length / maxMotionPoints
        var out = []
        var i
        for (i = 0; i < maxMotionPoints; ++i) {
            var idx = Math.min(points.length - 1, Math.floor(i * step))
            out.push(points[idx])
        }
        motionPoints = out
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

    function mapWidth() {
        return Math.max(1, width - 8)
    }

    function zoomAt(cursorX, factor) {
        if (_viewLock)
            return
        followLive = false
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var w = mapWidth()
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
        if (_viewLock)
            return
        followLive = false
        var s = effectiveStartTs()
        var e = effectiveEndTs()
        var w = mapWidth()
        var span = e - s
        var dt = -(dx / w) * span
        viewStartTs += dt
        viewEndTs += dt
        clampView()
    }

    // Must NOT be named such that onResetZoom: resetZoom() re-emits the signal
    function resetZoom() {
        if (_viewLock)
            return
        _fixedDayMode = false
        followLive = true
        _viewLock = true

        var nowSec = Date.now() / 1000
        var de = dataEndBound()
        var ds = dataStartBound()
        var end = Math.min(de, nowSec)
        var start = end - defaultViewSpan
        if (start < ds)
            start = ds
        if (end <= start)
            end = start + minViewSpan

        viewStartTs = start
        viewEndTs = end
        _viewLock = false
    }

    function timestampToX(tsMs) {
        var s = viewStartTs
        var e = viewEndTs
        if (!(e > s)) {
            s = dataStartBound()
            e = dataEndBound()
        }
        var w = Math.max(1, width - 8)
        if (e <= s)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    function xToTimestamp(x) {
        var s = viewStartTs
        var e = viewEndTs
        if (!(e > s)) {
            s = dataStartBound()
            e = dataEndBound()
        }
        var w = Math.max(1, width - 8)
        var ratio = Math.max(0, Math.min(1, x / w))
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
            if (Number(motionPoints[i].motion || 0) >= minMotion)
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
        return (span / 3600).toFixed(1) + "h"
    }

    function dayHasRecording(y, m, d) {
        var mm = (m < 10 ? "0" : "") + m
        var dd = (d < 10 ? "0" : "") + d
        var key = y + "-" + mm + "-" + dd
        if (recordingDays && recordingDays.length > 0) {
            for (var i = 0; i < recordingDays.length; ++i) {
                if (String(recordingDays[i]) === key)
                    return true
            }
            return false
        }
        if (!recordings || recordings.length === 0)
            return false
        var dayStart = new Date(y, m - 1, d, 0, 0, 0).getTime() / 1000
        var dayEnd = dayStart + 86400
        for (var j = 0; j < recordings.length; ++j) {
            var s = normalizeSec(recordings[j].start)
            var e = normalizeSec(recordings[j].end)
            if (e > dayStart && s < dayEnd)
                return true
        }
        return false
    }

    function jumpToDay(y, m, d) {
        var dayStart = new Date(y, m - 1, d, 0, 0, 0).getTime() / 1000
        var dayEnd = dayStart + 86400
        _fixedDayMode = true
        followLive = false
        timelineLoading = true
        refreshing = true
        dayLoadWatchdog.restart()
        if (dayStart < dataStartBound())
            dataStartTs = dayStart
        if (dayEnd > dataEndBound())
            dataEndTs = dayEnd
        viewStartTs = dayStart
        viewEndTs = dayEnd
        clampView()
        calendarPopup.visible = false
        calendarOpen = false

        var id = cameraId !== "" ? cameraId : cameraName
        if (frigateRef && id !== "") {
            if (typeof frigateRef.loadRecordingsForDay === "function")
                frigateRef.loadRecordingsForDay(id, Math.floor(dayStart), Math.floor(dayEnd))
            else if (typeof frigateRef.loadRecordingsRange === "function")
                frigateRef.loadRecordingsRange(id, Math.floor(dayStart), Math.floor(dayEnd))
            if (typeof frigateRef.loadEventsRange === "function")
                frigateRef.loadEventsRange(id, Math.floor(dayStart), Math.floor(dayEnd))
            if (typeof frigateRef.loadMotionActivityRange === "function")
                frigateRef.loadMotionActivityRange(id, Math.floor(dayStart), Math.floor(dayEnd))
        }
    }

    Component.onCompleted: {
        Qt.callLater(updatePlayhead)
    }

    Text {
        anchors.top: parent.top
        anchors.topMargin: 4
        anchors.horizontalCenter: parent.horizontalCenter
        z: 100
        visible: !collapsed && timelineLoading
        text: "Timeline loading"
        color: NxStyle.text
        font.pixelSize: 12
        font.bold: true
    }

    TimelineStatusBar {
        id: statusBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        visible: !collapsed
        z: 20
        timeline: timeline
        calendarOpen: timeline.calendarOpen
        exportBusy: timeline.exportBusy
        exportPercent: timeline.exportPercent
        onCalendarToggled: {
            if (!calendarPopup.visible) {
                var d = new Date(timeline.effectiveStartTs() * 1000)
                calendarPopup.calYear = d.getFullYear()
                calendarPopup.calMonth = d.getMonth() + 1
                var id = cameraId !== "" ? cameraId : cameraName
                if (frigateRef && typeof frigateRef.loadRecordingDays === "function" && id !== "")
                    frigateRef.loadRecordingDays(id)
            }
            calendarPopup.visible = !calendarPopup.visible
        }
        // Qualify with timeline. — bare resetZoom() re-emits statusBar's signal (stack overflow)
        onZoomOut: timeline.zoomAt(timeline.mapWidth() / 2, 0.7)
        onZoomIn: timeline.zoomAt(timeline.mapWidth() / 2, 1.4)
        onResetZoom: timeline.resetZoom()
        onExportRequested: timeline.requestExport()
        onClearExportRange: timeline.clearExportRange()
        onCancelExportRequested: timeline.cancelExport()
    }

    TimelineRuler {
        id: ruler
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusBar.bottom
        anchors.topMargin: 2
        startTs: timeline.viewStartTs > 0 ? timeline.viewStartTs : 0
        endTs: timeline.viewEndTs > timeline.viewStartTs ? timeline.viewEndTs : 1
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
            timeline.seekRequested(tsMs)
        }
        onRefreshRequested: timeline.requestRecordingsRefresh()
        onHoverTimeChanged: function(tsMs) {
            timeline.hoverTsMs = tsMs
            cursorLine.visible = tsMs > 0
            if (tsMs > 0)
                cursorLine.x = track.x + timeline.timestampToX(tsMs) - 1
        }
    }

    Item {
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
        onVisibleChanged: {
            timeline.calendarOpen = visible
            emitHover(visible || timeline.pointerInside || timeline.isExportUiOpen())
        }
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
                 + events.length + " events — wheel=zoom, Shift+drag=pan, drag=export range"
        }
        color: "#777777"
        font.pixelSize: 10
        visible: !collapsed
        z: 5
    }

    Loader {
        id: exportConfirmLoader
        active: false
        source: "qrc:/app/resources/qml/fullscreen/ExportConfirmPopup.qml"
        onLoaded: {
            item.confirmed.connect(function(sMs, eMs) {
                timeline.startExportDownload(sMs, eMs)
            })
            item.visibleChanged.connect(function() {
                if (item.visible) {
                    timeline.allowAutoReveal = true
                    timeline.collapsed = false
                }
                timeline.refreshExportUiOpen()
                emitHover(timeline.pointerInside || timeline.isExportUiOpen())
            })
        }
    }

    FileDialog {
        id: exportFileDialog
        title: "Export footage"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Video (*.mp4)"]
        defaultSuffix: "mp4"
        onAccepted: {
            var path = selectedFile.toString()
            if (path.indexOf("file:///") === 0)
                path = path.substring(8)
            else if (path.indexOf("file://") === 0)
                path = path.substring(7)
            path = decodeURIComponent(path)

            var id = cameraId !== "" ? cameraId : cameraName
            var startSec = Math.floor(exportStartMs / 1000)
            var endSec = Math.ceil(exportEndMs / 1000)
            if (endSec <= startSec)
                endSec = startSec + 1

            exportStallTimer.stop()
            exportDoneClearTimer.stop()
            exportBusy = true
            exportPercent = -1
            exportStatusMessage = ""
            exportBytesReceived = 0
            exportBytesPerSec = 0
            exportEtaSec = -1
            _lastProgressUiAt = 0
            _progressSampleAt = 0
            _progressSampleBytes = 0
            refreshExportUiOpen()
            frigateRef.exportClip(id, startSec, endSec, path)
        }
        onRejected: {
            refreshExportUiOpen()
            emitHover(pointerInside || isExportUiOpen())
        }
    }
}