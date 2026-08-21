import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0

Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 100000

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var subQueue: null
    property var mainQueue: null
    property var playbackQueue: null
    property bool isOnline: false
    property bool closeEnabled: false

    property alias mainReady: liveLayers.mainReady
    /** true only when C++ confirmed the real _main profile opened */
    property bool trueMain: false

    property bool isPlayback: false
    property bool playbackReady: false
    property real _lastSeekTs: -1
    property double _lastSeekWall: 0
    property int loadSecs: 0
    property bool timelinePointerInside: false
    property bool _returningLive: false
    property int _seekGen: 0
    property int _activeSeekGen: -1

    signal requestClose()

    onSubQueueChanged: liveLayers.subQueue = subQueue
    onMainQueueChanged: liveLayers.mainQueue = mainQueue
    onFrigateRefChanged: {
        liveLayers.frigateRef = frigateRef
        apiConn.target = frigateRef
    }
    onCameraNameChanged: liveLayers.cameraName = cameraName
    onCameraIdChanged: liveLayers.cameraId = cameraId
    onIsPlaybackChanged: {
        liveLayers.isPlayback = isPlayback
        if (timelineLoader.item)
            timelineLoader.item.isPlayback = isPlayback
    }
    onPlaybackReadyChanged: liveLayers.playbackReady = playbackReady

    onPlaybackQueueChanged: {
        playbackQueueConn.target = playbackQueue
        playbackVideo.queue = playbackQueue
        if (isPlayback && playbackQueue && !playbackReady
                && root._activeSeekGen >= 0
                && root._activeSeekGen === root._seekGen)
            forcePlaybackTimer.restart()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        z: -1
    }

    LiveFullscreenLayers {
        id: liveLayers
        anchors.fill: parent
        z: 0
        cameraId: root.cameraId
        cameraName: root.cameraName
        frigateRef: root.frigateRef
        subQueue: root.subQueue
        mainQueue: root.mainQueue
        isPlayback: root.isPlayback
        playbackReady: root.playbackReady
    }

    CameraVideoItem {
        id: playbackVideo
        anchors.fill: parent
        z: 2
        opacity: root.playbackReady ? 1.0 : 0.0
        queue: root.playbackQueue

        onFramePresented: {
            if (root.isPlayback && !root.playbackReady)
                root.markPlaybackReady()
        }
        onHasFrameChanged: {
            if (hasFrame && root.isPlayback && !root.playbackReady)
                root.markPlaybackReady()
        }
    }

    Connections {
        id: playbackQueueConn
        target: root.playbackQueue
        ignoreUnknownSignals: true
        function onFrameReady() {
            if (root.isPlayback && !root.playbackReady)
                root.markPlaybackReady()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.7, 440)
        height: 80
        radius: 10
        color: "#CC000000"
        border.color: "#FFC107"
        border.width: 1
        z: 50
        visible: root.isPlayback && !root.playbackReady
        Column {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "LOADING CLIP... " + root.loadSecs + "s"
                color: "#FFC107"
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Live stays on until first clip frame"
                color: "#FF8888"
                font.pixelSize: 13
            }
        }
    }

    Timer {
        interval: 1000
        running: root.isPlayback && !root.playbackReady
        repeat: true
        onTriggered: root.loadSecs++
    }

    Connections {
        id: apiConn
        target: root.frigateRef
        ignoreUnknownSignals: true

        function onRecordingsLoaded(id, segments) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            applyRecordings(segments)
        }

        function onPlaybackStarted(id) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            root.isPlayback = true
            root._activeSeekGen = root._seekGen
            forcePlaybackTimer.ticks = 0
            forcePlaybackTimer.restart()
        }

        function onPlaybackStopped(id) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            if (root._returningLive)
                return

            if (root.isPlayback && root.playbackReady)
                return

            if (root.isPlayback && !root.playbackReady) {
                root.isPlayback = false
                root.playbackReady = false
                root.loadSecs = 0
                root._activeSeekGen = -1
                forcePlaybackTimer.stop()
                playbackVideo.queue = null
                root.playbackQueue = null
                playbackQueueConn.target = null
            }
        }

        function onFullscreenMainStatus(name, isTrueMain) {
            if (name === root.cameraId || name === root.cameraName)
                root.trueMain = isTrueMain
        }
    }

    Timer {
        id: forcePlaybackTimer
        interval: 100
        repeat: true
        running: false
        property int ticks: 0
        onTriggered: {
            ticks++
            if (!root.isPlayback || root.playbackReady) {
                stop()
                return
            }
            if (root._activeSeekGen < 0 || root._seekGen !== root._activeSeekGen)
                return

            if (playbackVideo.hasFrame) {
                root.markPlaybackReady()
                stop()
                return
            }
            if (root.playbackQueue
                    && typeof root.playbackQueue.hasReceivedFrames === "function"
                    && root.playbackQueue.hasReceivedFrames()) {
                root.markPlaybackReady()
                stop()
                return
            }
            if (root.playbackQueue
                    && typeof root.playbackQueue.hasFrames === "function"
                    && root.playbackQueue.hasFrames()) {
                root.markPlaybackReady()
                stop()
                return
            }
            if (ticks > 200) {
                stop()
                root.isPlayback = false
                root.playbackReady = false
                root.loadSecs = 0
                root._activeSeekGen = -1
                playbackVideo.queue = null
                root.playbackQueue = null
                if (frigateRef && typeof frigateRef.switchToLive === "function") {
                    var id = root.cameraId !== "" ? root.cameraId : root.cameraName
                    frigateRef.switchToLive(id)
                }
            }
        }
    }

    Timer {
        id: closeArmTimer
        interval: 400
        onTriggered: root.closeEnabled = true
    }

    Timer {
        id: timelineHideTimer
        interval: 1800
        onTriggered: {
            if (!timelineLoader.item)
                return
            if (root.timelinePointerInside || bottomEdge.containsMouse)
                return
            if (typeof timelineLoader.item.hideTimeline === "function")
                timelineLoader.item.hideTimeline()
            else
                timelineLoader.item.collapsed = true
        }
    }

    Timer {
        id: recordingsPollTimer
        interval: 400
        repeat: true
        running: false
        property int tries: 0
        onTriggered: {
            tries++
            var id = root.cameraId !== "" ? root.cameraId : root.cameraName
            if (frigateRef && typeof frigateRef.getRecordingsForCamera === "function") {
                var segs = frigateRef.getRecordingsForCamera(id)
                if (segs && segs.length > 0) {
                    applyRecordings(segs)
                    stop()
                    return
                }
            }
            if (tries >= 20)
                stop()
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        z: 20
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape && root.closeEnabled) {
                root.tryExit()
                event.accepted = true
            }
        }
    }

    MouseArea {
        id: videoClickArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: timelineLoader.height > 0 ? timelineLoader.height : 0
        z: 25
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: false
        onDoubleClicked: function(mouse) {
            mouse.accepted = true
            root.tryExit()
        }
    }

    Rectangle {
        height: 36
        width: parent.width
        anchors.top: parent.top
        color: "#00000099"
        z: 30
        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 16
            Text {
                text: root.cameraName
                color: "white"
                font.pixelSize: 15
                font.bold: true
            }
            Text {
                text: {
                    if (!root.isPlayback)
                        return "LIVE"
                    if (!root.playbackReady)
                        return "LOADING..."
                    return "PLAYBACK"
                }
                color: root.isPlayback ? "#FFC107" : "#00C853"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                text: root.playbackReady ? "" : ((liveLayers.mainReady && root.trueMain) ? "MAIN" : "SUB")
                color: (liveLayers.mainReady && root.trueMain) ? "#FFC107" : "#90CAF9"
                font.pixelSize: 13
            }
        }
    }

    Rectangle {
        width: 70
        height: 28
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 90
        anchors.topMargin: 10
        radius: 4
        color: root.playbackReady ? "#1B5E20" : "#00000055"
        border.color: root.playbackReady ? "#00C853" : "#444"
        border.width: 1
        z: 31
        visible: root.isPlayback
        Text {
            anchors.centerIn: parent
            text: "Live"
            color: "white"
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.playbackReady
            preventStealing: true
            onClicked: function(mouse) {
                mouse.accepted = true
                root.returnToLive()
            }
        }
    }

    Rectangle {
        width: 70
        height: 28
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        radius: 4
        color: "#000000AA"
        z: 31
        Text {
            anchors.centerIn: parent
            text: "Exit"
            color: "white"
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true
                root.tryExit()
            }
        }
    }

    Loader {
        id: timelineLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 40
        height: item ? Math.max(item.height, 0) : 0
        source: "qrc:/app/resources/qml/fullscreen/FullscreenTimeline.qml"
        active: true
        onLoaded: {
            applyTimelineCamera()
            if (item) {
                try { item.seekRequested.disconnect(root.onTimelineSeek) } catch (e) {}
                item.seekRequested.connect(root.onTimelineSeek)
                try { item.hoverActiveChanged.disconnect(root.onTimelineHoverActive) } catch (e2) {}
                if (item.hoverActiveChanged)
                    item.hoverActiveChanged.connect(root.onTimelineHoverActive)
            }
        }
    }

    MouseArea {
        id: bottomEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: (timelineLoader.item && !timelineLoader.item.collapsed) ? 0 : 56
        z: 36
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        visible: height > 0
        onEntered: {
            showTimelineBar()
            timelineHideTimer.stop()
        }
        onExited: {
            if (!root.timelinePointerInside)
                timelineHideTimer.restart()
        }
        onPositionChanged: {
            showTimelineBar()
            timelineHideTimer.stop()
        }
    }

    function onTimelineHoverActive(active) {
        root.timelinePointerInside = active
        if (active) {
            timelineHideTimer.stop()
            showTimelineBar()
        } else {
            timelineHideTimer.restart()
        }
    }

    function markPlaybackReady() {
        if (root.playbackReady)
            return
        if (root._activeSeekGen < 0 || root._seekGen !== root._activeSeekGen)
            return

        root.playbackReady = true
        root.loadSecs = 0
        forcePlaybackTimer.stop()

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        if (typeof liveLayers.pauseMainForPlayback === "function")
            liveLayers.pauseMainForPlayback()
        root.mainQueue = null
        if (frigateRef && typeof frigateRef.stopFullscreenStream === "function") {
            Qt.callLater(function() {
                if (frigateRef && typeof frigateRef.stopFullscreenStream === "function")
                    frigateRef.stopFullscreenStream(id)
            })
        }
    }

    function tryExit() {
        root.requestClose()
    }

    function showTimelineBar() {
        if (!timelineLoader.item)
            return
        timelineLoader.item.allowAutoReveal = true
        timelineLoader.item.collapsed = false
        timelineHideTimer.stop()
    }

    function applyTimelineCamera() {
        if (!timelineLoader.item)
            return
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        timelineLoader.item.cameraId = id
        timelineLoader.item.cameraName = root.cameraName
        timelineLoader.item.frigateRef = root.frigateRef
        timelineLoader.item.allowAutoReveal = true
        timelineLoader.item.collapsed = true
        timelineLoader.item.isPlayback = root.isPlayback
        root.timelinePointerInside = false
    }

    function applyRecordings(segments) {
        if (!timelineLoader.item)
            return
        timelineLoader.item.recordings = segments
        if (segments && segments.length > 0) {
            timelineLoader.item.startTs = segments[0].start
            timelineLoader.item.endTs = segments[segments.length - 1].end
        }
    }

    function onTimelineSeek(tsMs) {
        if (!frigateRef)
            return
        var wall = Date.now()
        if (Math.abs(tsMs - root._lastSeekTs) < 200 && (wall - root._lastSeekWall) < 300)
            return
        root._lastSeekTs = tsMs
        root._lastSeekWall = wall

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName

        root._seekGen++
        root._activeSeekGen = -1

        root.isPlayback = true
        root.playbackReady = false
        root.loadSecs = 0
        root._returningLive = false
        forcePlaybackTimer.ticks = 0
        forcePlaybackTimer.stop()

        showTimelineBar()

        playbackVideo.queue = null
        playbackQueueConn.target = null
        root.playbackQueue = null

        if (typeof frigateRef.startPlayback === "function")
            frigateRef.startPlayback(id, Math.floor(tsMs))
        else if (typeof frigateRef.seek === "function")
            frigateRef.seek(id, Math.floor(tsMs))

        if (typeof frigateRef.getPlaybackQueue === "function") {
            root.playbackQueue = frigateRef.getPlaybackQueue(id)
            playbackVideo.queue = root.playbackQueue
            playbackQueueConn.target = root.playbackQueue
        }

        if (timelineLoader.item) {
            timelineLoader.item.isPlayback = true
            timelineLoader.item.playbackPositionMs = tsMs
        }
    }

    function returnToLive() {
        if (root._returningLive)
            return
        if (!root.playbackReady && root.isPlayback)
            return

        root._returningLive = true

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName

        root.isPlayback = false
        root.playbackReady = false
        root.loadSecs = 0
        root._activeSeekGen = -1
        forcePlaybackTimer.stop()

        playbackVideo.queue = null
        root.playbackQueue = null
        playbackQueueConn.target = null

        if (timelineLoader.item) {
            timelineLoader.item.isPlayback = false
            timelineLoader.item.playbackPositionMs = 0
        }

        if (frigateRef && typeof frigateRef.switchToLive === "function")
            frigateRef.switchToLive(id)

        if (typeof liveLayers.resumeMain === "function")
            liveLayers.resumeMain(id)
        root.mainQueue = liveLayers.mainQueue
        root.trueMain = false
        if (frigateRef && typeof frigateRef.isFullscreenTrueMain === "function")
            root.trueMain = frigateRef.isFullscreenTrueMain(id)

        Qt.callLater(function() {
            root._returningLive = false
        })
    }

    function loadTimelineData() {
        if (!frigateRef)
            return
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        if (id === "")
            return
        if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)
        if (typeof frigateRef.loadEvents === "function")
            frigateRef.loadEvents(id)
        if (typeof frigateRef.loadMotionActivity === "function")
            frigateRef.loadMotionActivity(id)
        recordingsPollTimer.tries = 0
        recordingsPollTimer.start()
    }

    function open() {
        closeEnabled = false
        isPlayback = false
        playbackReady = false
        loadSecs = 0
        timelinePointerInside = false
        _returningLive = false
        _seekGen = 0
        _activeSeekGen = -1
        trueMain = false
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()
        apiConn.target = frigateRef

        liveLayers.cameraId = root.cameraId
        liveLayers.cameraName = root.cameraName
        liveLayers.frigateRef = root.frigateRef
        liveLayers.subQueue = root.subQueue
        liveLayers.mainQueue = root.mainQueue
        liveLayers.isPlayback = false
        liveLayers.playbackReady = false
        liveLayers.startLive()

        playbackQueueConn.target = null
        playbackVideo.queue = null

        applyTimelineCamera()
        loadTimelineData()
    }

    function close() {
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName

        forcePlaybackTimer.stop()
        liveLayers.stopLive()

        playbackQueueConn.target = null
        playbackVideo.queue = null
        root.mainQueue = null
        root.subQueue = null
        root.playbackQueue = null
        root.trueMain = false

        if (frigateRef && typeof frigateRef.stopFullscreenStream === "function")
            frigateRef.stopFullscreenStream(id)

        if (frigateRef) {
            if (typeof frigateRef.switchToLive === "function")
                frigateRef.switchToLive(id)
            else if (typeof frigateRef.stopPlayback === "function")
                frigateRef.stopPlayback(id)
        }

        isPlayback = false
        playbackReady = false
        loadSecs = 0
        timelinePointerInside = false
        _returningLive = false
        _seekGen = 0
        _activeSeekGen = -1
        closeArmTimer.stop()
        timelineHideTimer.stop()
        recordingsPollTimer.stop()
        closeEnabled = false
        visible = false

        if (timelineLoader.item) {
            timelineLoader.item.allowAutoReveal = false
            timelineLoader.item.collapsed = true
            timelineLoader.item.isPlayback = false
        }
    }
}