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
    property bool timelinePointerInside: false

    signal requestClose()

    onSubQueueChanged: {
        if (!root.isPlayback)
            subVideo.queue = subQueue
    }

    onMainQueueChanged: {
        mainQueueConn.target = mainQueue
        if (!root.isPlayback) {
            root.mainReady = false
            mainVideo.queue = mainQueue
            if (visible && mainQueue) {
                forceMainTimer.restart()
                if (typeof mainQueue.hasReceivedFrames === "function" && mainQueue.hasReceivedFrames())
                    promoteMain("queue already had frames")
            }
        }
    }

    onFrigateRefChanged: apiConn.target = frigateRef

    Rectangle { anchors.fill: parent; color: "black" }

    // SUB layer - visible until MAIN has frames
    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        opacity: (!root.isPlayback && !root.mainReady) ? 1.0 : 0.0
        queue: subQueue
    }

    // MAIN / HQ layer
    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        opacity: root.isPlayback ? 0.0 : (root.mainReady ? 1.0 : 0.05)
        queue: mainQueue
        onFramePresented: {
            if (!root.isPlayback)
                promoteMain("mainVideo.framePresented")
        }
        onHasFrameChanged: {
            if (hasFrame && !root.isPlayback)
                promoteMain("mainVideo.hasFrame")
        }
    }

    CameraVideoItem {
        id: playbackVideo
        anchors.fill: parent
        z: 2
        opacity: root.playbackReady ? 1.0 : 0.0
        queue: playbackQueue
    }

    Connections {
        id: mainQueueConn
        target: mainQueue
        ignoreUnknownSignals: true
        function onFrameReady() {
            if (!root.isPlayback)
                promoteMain("mainQueue.frameReady")
        }
    }

    Connections {
        id: apiConn
        target: frigateRef
        ignoreUnknownSignals: true

        function onFullscreenFrameReady(name) {
            if (root.isPlayback)
                return
            if (name === root.cameraName || name === root.cameraId)
                promoteMain("fullscreenFrameReady")
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
        }
    }

    // Poll until MAIN frames appear
    Timer {
        id: forceMainTimer
        interval: 50
        repeat: true
        running: false
        property int ticks: 0
        onTriggered: {
            if (root.isPlayback || root.mainReady) {
                stop()
                return
            }
            ticks++
            if (mainVideo.hasFrame) {
                promoteMain("forceMainTimer.hasFrame")
                return
            }
            if (root.mainQueue && typeof root.mainQueue.hasReceivedFrames === "function"
                    && root.mainQueue.hasReceivedFrames()) {
                promoteMain("forceMainTimer.hasReceivedFrames")
                return
            }
            if (root.mainQueue && typeof root.mainQueue.hasFrames === "function"
                    && root.mainQueue.hasFrames()) {
                promoteMain("forceMainTimer.hasFrames")
                return
            }
            // Give up polling after ~15s; stay on SUB
            if (ticks > 300)
                stop()
        }
    }

    Timer { id: closeArmTimer; interval: 400; onTriggered: root.closeEnabled = true }

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
                text: root.isPlayback ? (root.playbackReady ? "PLAYBACK" : "LOADING...") : "LIVE"
                color: root.isPlayback ? "#FFC107" : "#00C853"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                text: root.isPlayback ? "" : (root.mainReady ? "MAIN" : "SUB")
                color: root.mainReady ? "#FFC107" : "#90CAF9"
                font.pixelSize: 13
                font.bold: true
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

    function promoteMain(reason) {
        if (root.mainReady || root.isPlayback)
            return
        root.mainReady = true
        forceMainTimer.stop()
        console.log("Fullscreen SUB -> MAIN", root.cameraName, reason)
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
        // Playback left as-is; not the focus of this change
        if (!frigateRef)
            return
        var wall = Date.now()
        if (Math.abs(tsMs - root._lastSeekTs) < 200 && (wall - root._lastSeekWall) < 300)
            return
        root._lastSeekTs = tsMs
        root._lastSeekWall = wall

        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        root.isPlayback = true
        root.playbackReady = false
        root.loadSecs = 0

        if (typeof frigateRef.getPlaybackQueue === "function") {
            root.playbackQueue = frigateRef.getPlaybackQueue(id)
            playbackVideo.queue = root.playbackQueue
        }
        if (typeof frigateRef.startPlayback === "function")
            frigateRef.startPlayback(id, Math.floor(tsMs))
        else if (typeof frigateRef.seek === "function")
            frigateRef.seek(id, Math.floor(tsMs))
    }

    function returnToLive() {
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName
        root.isPlayback = false
        root.playbackReady = false
        playbackVideo.queue = null
        root.playbackQueue = null

        if (frigateRef && typeof frigateRef.switchToLive === "function")
            frigateRef.switchToLive(id)

        if (root.subQueue)
            subVideo.queue = root.subQueue

        root.mainReady = false
        if (frigateRef && typeof frigateRef.getFullscreenQueue === "function") {
            root.mainQueue = frigateRef.getFullscreenQueue(id)
            mainVideo.queue = root.mainQueue
            mainQueueConn.target = root.mainQueue
            forceMainTimer.ticks = 0
            forceMainTimer.restart()
        }
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
        console.log("Fullscreen open", root.cameraName)

        closeEnabled = false
        isPlayback = false
        playbackReady = false
        mainReady = false
        loadSecs = 0
        timelinePointerInside = false
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()

        apiConn.target = frigateRef
        mainQueueConn.target = mainQueue

        playbackVideo.queue = null
        subVideo.queue = subQueue
        mainVideo.queue = mainQueue

        forceMainTimer.ticks = 0
        if (mainQueue) {
            forceMainTimer.restart()
            if (typeof mainQueue.hasReceivedFrames === "function" && mainQueue.hasReceivedFrames())
                promoteMain("open() existing frames")
        } else {
            console.log("Fullscreen open: mainQueue is null")
        }

        applyTimelineCamera()
        loadTimelineData()
    }

    function close() {
        var id = root.cameraId !== "" ? root.cameraId : root.cameraName

        forceMainTimer.stop()
        mainQueueConn.target = null
        mainVideo.queue = null
        subVideo.queue = null
        playbackVideo.queue = null
        root.mainQueue = null
        root.subQueue = null
        root.playbackQueue = null

        if (frigateRef && typeof frigateRef.switchToLive === "function")
            frigateRef.switchToLive(id)

        isPlayback = false
        playbackReady = false
        mainReady = false
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