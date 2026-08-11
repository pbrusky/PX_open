import QtQuick 2.15
import PxOpen 1.0

// ============================================================
// LIVE SUB + MAIN layers only.
// Do not put timeline or playback logic in this file.
// Tag: fullscreen-main-ok behavior lives here.
// ============================================================
Item {
    id: live
    anchors.fill: parent

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var subQueue: null
    property var mainQueue: null

    // Driven by FullscreenCamera shell
    property bool isPlayback: false
    property bool playbackReady: false

    property bool mainReady: false

    signal mainPromoted(string reason)

    onSubQueueChanged: {
        if (!playbackReady)
            subVideo.queue = subQueue
    }

    onMainQueueChanged: {
        mainQueueConn.target = mainQueue
        if (!isPlayback && !playbackReady)
            mainReady = false
        if (!isPlayback)
            mainVideo.queue = mainQueue
        if (visible && mainQueue && !isPlayback && !playbackReady) {
            forceMainTimer.restart()
            if (typeof mainQueue.hasReceivedFrames === "function"
                    && mainQueue.hasReceivedFrames()) {
                promoteMain("onMainQueueChanged existing frames")
            }
        }
    }

    onFrigateRefChanged: apiConn.target = frigateRef

    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        opacity: (!live.playbackReady && !live.mainReady) ? 1.0 : 0.0
        queue: live.subQueue
    }

    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        opacity: live.playbackReady ? 0.0 : (live.mainReady ? 1.0 : 0.02)
        queue: live.mainQueue

        onFramePresented: {
            if (!live.isPlayback && !live.playbackReady)
                promoteMain("mainVideo.framePresented")
        }

        onHasFrameChanged: {
            if (hasFrame && !live.isPlayback && !live.playbackReady)
                promoteMain("mainVideo.hasFrame")
        }
    }

    Connections {
        id: mainQueueConn
        target: live.mainQueue
        ignoreUnknownSignals: true

        function onFrameReady() {
            if (!live.isPlayback && !live.playbackReady)
                promoteMain("mainQueue.frameReady")
        }
    }

    Connections {
        id: apiConn
        target: live.frigateRef
        ignoreUnknownSignals: true

        function onFullscreenFrameReady(name) {
            if (live.isPlayback || live.playbackReady)
                return
            if (name === live.cameraName || name === live.cameraId)
                promoteMain("fullscreenFrameReady")
        }
    }

    Timer {
        id: forceMainTimer
        interval: 50
        repeat: true
        running: false
        property int ticks: 0

        onTriggered: {
            ticks++
            if (live.isPlayback || live.playbackReady || live.mainReady) {
                stop()
                return
            }
            if (mainVideo.hasFrame) {
                promoteMain("forceMainTimer.hasFrame")
                return
            }
            if (live.mainQueue
                    && typeof live.mainQueue.hasReceivedFrames === "function"
                    && live.mainQueue.hasReceivedFrames()) {
                promoteMain("forceMainTimer.hasReceivedFrames")
                return
            }
            if (live.mainQueue
                    && typeof live.mainQueue.hasFrames === "function"
                    && live.mainQueue.hasFrames()) {
                promoteMain("forceMainTimer.hasFrames")
                return
            }
            // Give up after ~5s; stay on SUB
            if (ticks > 100)
                stop()
        }
    }

    function promoteMain(reason) {
        if (live.mainReady || live.isPlayback || live.playbackReady)
            return
        live.mainReady = true
        forceMainTimer.stop()
        console.log("Fullscreen SUB -> MAIN", live.cameraName, reason)
        live.mainPromoted(reason)
    }

    // Call when entering fullscreen (live mode)
    function startLive() {
        live.mainReady = false
        forceMainTimer.ticks = 0
        apiConn.target = live.frigateRef
        mainQueueConn.target = live.mainQueue
        subVideo.queue = live.subQueue
        mainVideo.queue = live.mainQueue
        if (live.mainQueue) {
            forceMainTimer.restart()
            if (typeof live.mainQueue.hasReceivedFrames === "function"
                    && live.mainQueue.hasReceivedFrames()) {
                promoteMain("startLive existing frames")
            }
        } else {
            forceMainTimer.stop()
        }
    }

    // Keep SUB visible; drop MAIN while clip loads
    function pauseMainForPlayback() {
        forceMainTimer.stop()
        mainQueueConn.target = null
        mainVideo.queue = null
        live.mainQueue = null
        live.mainReady = false
        if (live.subQueue)
            subVideo.queue = live.subQueue
    }

    // After Live button / return from playback
    function resumeMain(id) {
        if (live.subQueue)
            subVideo.queue = live.subQueue

        if (live.frigateRef
                && typeof live.frigateRef.getFullscreenQueue === "function") {
            live.mainQueue = live.frigateRef.getFullscreenQueue(id)
            mainVideo.queue = live.mainQueue
            mainQueueConn.target = live.mainQueue
            live.mainReady = false
            forceMainTimer.ticks = 0
            forceMainTimer.restart()
        }
    }

    function stopLive() {
        forceMainTimer.stop()
        mainQueueConn.target = null
        mainVideo.queue = null
        subVideo.queue = null
        live.mainQueue = null
        live.subQueue = null
        live.mainReady = false
    }
}