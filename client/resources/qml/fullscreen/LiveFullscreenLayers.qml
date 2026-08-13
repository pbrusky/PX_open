import QtQuick 2.15
import PxOpen 1.0

Item {
    id: live
    anchors.fill: parent

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var subQueue: null
    property var mainQueue: null

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
        if (!playbackReady)
            mainReady = false
        if (!playbackReady)
            mainVideo.queue = mainQueue
        if (mainQueue && !playbackReady) {
            forceMainTimer.ticks = 0
            forceMainTimer.restart()
            tryPromote("onMainQueueChanged")
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
        opacity: live.playbackReady ? 0.0 : (live.mainReady ? 1.0 : 0.05)
        queue: live.mainQueue

        onFramePresented: tryPromote("mainVideo.framePresented")
        onHasFrameChanged: {
            if (hasFrame)
                tryPromote("mainVideo.hasFrame")
        }
    }

    Connections {
        id: mainQueueConn
        target: live.mainQueue
        ignoreUnknownSignals: true
        function onFrameReady() { tryPromote("mainQueue.frameReady") }
    }

    Connections {
        id: apiConn
        target: live.frigateRef
        ignoreUnknownSignals: true
        function onFullscreenFrameReady(name) {
            if (name === live.cameraName || name === live.cameraId)
                tryPromote("fullscreenFrameReady")
        }
    }

    Timer {
        id: forceMainTimer
        interval: 100
        repeat: true
        running: false
        property int ticks: 0
        onTriggered: {
            ticks++
            if (live.mainReady || live.playbackReady) {
                stop()
                return
            }
            if (live.mainQueue && mainVideo.queue !== live.mainQueue)
                mainVideo.queue = live.mainQueue

            tryPromote("forceMainTimer")

            if (ticks % 10 === 0) {
                var got = false
                if (live.mainQueue && typeof live.mainQueue.hasReceivedFrames === "function")
                    got = live.mainQueue.hasReceivedFrames()
                console.log("Fullscreen waiting MAIN", live.cameraName,
                            "ticks=", ticks, "hasFrame=", mainVideo.hasFrame, "received=", got)
            }
            if (ticks > 200) {
                console.log("Fullscreen MAIN timeout", live.cameraName)
                stop()
            }
        }
    }

    // Only block when a clip is actually on screen (playbackReady).
    // Do NOT block on isPlayback — that prevented promote forever.
    function tryPromote(reason) {
        if (live.mainReady || live.playbackReady)
            return

        var ok = false
        if (mainVideo.hasFrame)
            ok = true
        if (!ok && live.mainQueue && typeof live.mainQueue.hasReceivedFrames === "function"
                && live.mainQueue.hasReceivedFrames())
            ok = true
        if (!ok && live.mainQueue && typeof live.mainQueue.hasFrames === "function"
                && live.mainQueue.hasFrames())
            ok = true
        if (!ok)
            return

        live.mainReady = true
        forceMainTimer.stop()
        console.log("Fullscreen SUB -> MAIN", live.cameraName, reason)
        live.mainPromoted(reason)
    }

    function startLive() {
        live.mainReady = false
        live.playbackReady = false
        forceMainTimer.ticks = 0
        apiConn.target = live.frigateRef

        if (!live.mainQueue && live.frigateRef
                && typeof live.frigateRef.getFullscreenQueue === "function") {
            var id = live.cameraId !== "" ? live.cameraId : live.cameraName
            if (id !== "")
                live.mainQueue = live.frigateRef.getFullscreenQueue(id)
        }

        mainQueueConn.target = live.mainQueue
        subVideo.queue = live.subQueue
        mainVideo.queue = live.mainQueue

        console.log("Fullscreen startLive", live.cameraName,
                    "mainQueue=", live.mainQueue !== null && live.mainQueue !== undefined)

        if (live.mainQueue) {
            forceMainTimer.restart()
            tryPromote("startLive")
        } else {
            forceMainTimer.stop()
        }
    }

    function pauseMainForPlayback() {
        forceMainTimer.stop()
        mainQueueConn.target = null
        mainVideo.queue = null
        live.mainQueue = null
        live.mainReady = false
        if (live.subQueue)
            subVideo.queue = live.subQueue
    }

    function resumeMain(id) {
        if (live.subQueue)
            subVideo.queue = live.subQueue
        if (live.frigateRef && typeof live.frigateRef.getFullscreenQueue === "function") {
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