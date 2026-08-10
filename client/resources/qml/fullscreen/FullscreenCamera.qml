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
    property bool mainReady: false
    property bool isPlayback: false
    property bool playbackReady: false
    property real _lastSeekTs: -1
    property double _lastSeekWall: 0
    property int loadSecs: 0

    signal requestClose()

    onSubQueueChanged: subVideo.queue = subQueue
    onMainQueueChanged: {
        if (!playbackReady)
            mainReady = false
        mainVideo.queue = mainQueue
        if (visible && mainQueue && !playbackReady)
            forceMainTimer.restart()
    }
    onFrigateRefChanged: apiConn.target = frigateRef

    Rectangle { anchors.fill: parent; color: "black" }

    // Live SUB — stays visible until MAIN or playback frames arrive
    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        opacity: (!root.playbackReady && !root.mainReady) ? 1.0 : 0.0
        queue: subQueue
    }

    // Live MAIN / HQ fallback
    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        opacity: (!root.playbackReady && root.mainReady) ? 1.0 : 0.0
        queue: mainQueue
        onFramePresented: {
            if (!root.playbackReady) {
                root.mainReady = true
                forceMainTimer.stop()
            }
        }
        onHasFrameChanged: {
            if (hasFrame && !root.playbackReady) {
                root.mainReady = true
                forceMainTimer.stop()
            }
        }
    }

    // Playback — only shown after clip is open and frames exist
    CameraVideoItem {
        id: playbackVideo
        anchors.fill: parent
        z: 2
        opacity: root.playbackReady ? 1.0 : 0.0
        queue: playbackQueue
        onFramePresented: {
            if (root.isPlayback)
                root.playbackReady = true
        }
        onHasFrameChanged: {
            if (hasFrame && root.isPlayback)
                root.playbackReady = true
        }
    }

    // Loading banner — live video stays behind this
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.7, 480)
        height: 90
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
                text: "LOADING CLIP… " + root.loadSecs + "s"
                color: "#FFC107"
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Live video stays on — do not press Exit"
                color: "#FF8888"
                font.pixelSize: 14
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "4K clips can take 60–90 seconds on Wi‑Fi"
                color: "#AAAAAA"
                font.pixelSize: 12
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
        target: frigateRef
        ignoreUnknownSignals: true

        function onFullscreenFrameReady(name) {
            if (root.playbackReady)
                return
            if (name === root.cameraName || name === root.cameraId) {
                root.mainReady = true
                forceMainTimer.stop()
            }
        }

        function onRecordingsLoaded(id, segments) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            applyRecordings(segments)
        }

        function onPlaybackStarted(id) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            root.isPlayback = true
            root.playbackReady = true
            root.loadSecs = 0
            console.log("Playback started UI", id)
            // Free HQ bandwidth only after playback is actually running
            if (typeof frigateRef.stopFullscreenStream === "function")
                frigateRef.stopFullscreenStream(id)
        }

        function onPlaybackStopped(id) {
            // returnToLive / close clear flags
        }
    }

    Timer {
        id: forceMainTimer
        interval: 100
        repeat: true
        running: false
        onTriggered: {
            if (root.playbackReady || root.mainReady) {
                stop()
                return
            }
            if (mainVideo.hasFrame) {
                root.mainReady = true
                stop()
                return
            }
            if (root.mainQueue && typeof root.mainQueue.hasReceivedFrames === "function"
                    && root.mainQueue.hasReceivedFrames()) {
                root.mainReady = true
                stop()
                return
            }
            if (root.mainQueue && typeof root.mainQueue.hasFrames === "function"
                    && root.mainQueue.hasFrames()) {
                root.mainReady = true
                stop()
            }
        }
    }

    Timer { id: closeArmTimer; interval: 400; onTriggered: root.closeEnabled = true }

    Timer {
        id: timelineHideTimer
        interval: 2800
        onTriggered: {
            if (timelineLoader.item && !bottomEdge.containsMouse)
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
            console.log("Double-click exit fullscreen")
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
                        return "LOADING…"
                    return "PLAYBACK"
                }
                color: root.isPlayback ? "#FFC107" : "#00C853"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                text: root.playbackReady ? "" : (root.mainReady ? "MAIN" : "SUB")
                color: root.mainReady ? "#FFC107" : "#90CAF9"
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
        Text {
            anchors.centerIn: parent
            text: "Live"
            color: "white"
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.playbackReady
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
            }
        }
    }

    MouseArea {
        id: bottomEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: (timelineLoader.item && !timelineLoader.item.collapsed) ? 8 : 56
        z: 35
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: { showTimelineBar(); timelineHideTimer.stop() }
        onExited: timelineHideTimer.restart()
        onPositionChanged: { showTimelineBar(); timelineHideTimer.restart() }
    }

    function tryExit() {
        if (root.isPlayback && !root.playbackReady)
            console.log("Exit during LOADING — canceling download")
        root.requestClose()
    }

    function showTimelineBar() {
        if (!timelineLoader.item)
            return
        timelineLoader.item.allowAutoReveal = true
        timelineLoader.item.collapsed = false
    }

    function applyTimelineCamera() {
        if (!timelineLoader.item)
            return
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        timelineLoader.item.cameraId = id
        timelineLoader.item.cameraName = root.cameraName
        timelineLoader.item.frigateRef = root.frigateRef
        timelineLoader.item.allowAutoReveal = true
        timelineLoader.item.collapsed = false
        timelineLoader.item.isPlayback = root.isPlayback
        timelineHideTimer.restart()
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
        if (!frigateRef) {
            console.log("Seek ignored — no frigateRef")
            return
        }
        var wall = Date.now()
        if (Math.abs(tsMs - root._lastSeekTs) < 200 && (wall - root._lastSeekWall) < 300)
            return
        root._lastSeekTs = tsMs
        root._lastSeekWall = wall

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        console.log("Seek playback", id, "at", tsMs)

        root.isPlayback = true
        root.playbackReady = false
        root.loadSecs = 0
        // Keep live HQ running so the screen is not black while curl downloads

        if (typeof frigateRef.getPlaybackQueue === "function") {
            root.playbackQueue = frigateRef.getPlaybackQueue(id)
            playbackVideo.queue = root.playbackQueue
        }

        if (typeof frigateRef.startPlayback === "function")
            frigateRef.startPlayback(id, Math.floor(tsMs))
        else if (typeof frigateRef.seek === "function")
            frigateRef.seek(id, Math.floor(tsMs))
        else
            console.log("ERROR: no startPlayback/seek on frigateRef")

        if (timelineLoader.item) {
            timelineLoader.item.isPlayback = true
            timelineLoader.item.playbackPositionMs = tsMs
        }
    }

    function returnToLive() {
        if (!root.playbackReady) {
            console.log("returnToLive ignored (still loading)")
            return
        }

        console.log("returnToLive", root.cameraName)

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName

        root.isPlayback = false
        root.playbackReady = false
        root.loadSecs = 0
        playbackVideo.queue = null
        root.playbackQueue = null
        if (timelineLoader.item) {
            timelineLoader.item.isPlayback = false
            timelineLoader.item.playbackPositionMs = 0
        }

        if (frigateRef) {
            if (typeof frigateRef.switchToLive === "function")
                frigateRef.switchToLive(id)
            else if (typeof frigateRef.stopPlayback === "function")
                frigateRef.stopPlayback(id)
        }

        if (frigateRef && typeof frigateRef.getFullscreenQueue === "function") {
            root.mainQueue = frigateRef.getFullscreenQueue(id)
            mainVideo.queue = root.mainQueue
            root.mainReady = false
            forceMainTimer.restart()
        }
        if (root.subQueue)
            subVideo.queue = root.subQueue
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
        recordingsPollTimer.tries = 0
        recordingsPollTimer.start()
    }

    function open() {
        closeEnabled = false
        mainReady = false
        isPlayback = false
        playbackReady = false
        loadSecs = 0
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()
        apiConn.target = frigateRef
        subVideo.queue = subQueue
        mainVideo.queue = mainQueue
        playbackVideo.queue = null
        if (mainQueue)
            forceMainTimer.restart()
        applyTimelineCamera()
        loadTimelineData()
    }

    function close() {
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        if (frigateRef) {
            if (typeof frigateRef.stopPlayback === "function")
                frigateRef.stopPlayback(id)
            else if (typeof frigateRef.switchToLive === "function")
                frigateRef.switchToLive(id)
        }

        isPlayback = false
        playbackReady = false
        loadSecs = 0
        closeArmTimer.stop()
        forceMainTimer.stop()
        timelineHideTimer.stop()
        recordingsPollTimer.stop()
        closeEnabled = false
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
        playbackQueue = null
        subVideo.queue = null
        mainVideo.queue = null
        playbackVideo.queue = null
        if (timelineLoader.item) {
            timelineLoader.item.allowAutoReveal = false
            timelineLoader.item.collapsed = true
            timelineLoader.item.isPlayback = false
        }
    }
}