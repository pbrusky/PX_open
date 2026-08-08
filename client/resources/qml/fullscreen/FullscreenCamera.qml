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
    property bool isOnline: false
    property bool closeEnabled: false
    property bool mainReady: false

    signal requestClose()

    onSubQueueChanged: subVideo.queue = subQueue
    onMainQueueChanged: {
        mainReady = false
        mainVideo.queue = mainQueue
        if (visible && mainQueue)
            forceMainTimer.restart()
    }
    onFrigateRefChanged: apiConn.target = frigateRef

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        opacity: mainReady ? 0.0 : 1.0
        queue: subQueue
    }

    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        opacity: mainReady ? 1.0 : 0.0
        queue: mainQueue

        onFramePresented: {
            root.mainReady = true
            forceMainTimer.stop()
        }

        onHasFrameChanged: {
            if (hasFrame) {
                root.mainReady = true
                forceMainTimer.stop()
            }
        }
    }

    Connections {
        id: apiConn
        target: frigateRef
        ignoreUnknownSignals: true

        function onFullscreenFrameReady(name) {
            if (name === root.cameraName || name === root.cameraId)
                forceMainTimer.restart()
        }

        function onRecordingsLoaded(id, segments) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            applyRecordings(segments)
        }

        function onEventsLoaded(id, list) {
            if (id !== root.cameraId && id !== root.cameraName)
                return
            applyEvents(list)
        }
    }

    Timer {
        id: forceMainTimer
        interval: 100
        repeat: true
        running: false
        onTriggered: {
            if (root.mainReady) {
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
        interval: 2800
        onTriggered: {
            if (timelineLoader.item && !bottomEdge.containsMouse)
                timelineLoader.item.collapsed = true
        }
    }

    // Pull recordings if the signal was missed (race on open)
    Timer {
        id: recordingsPollTimer
        interval: 400
        repeat: true
        running: false
        property int tries: 0
        onTriggered: {
            tries++
            if (!frigateRef || !timelineLoader.item) {
                if (tries >= 15)
                    stop()
                return
            }
            var id = root.cameraId !== "" ? root.cameraId : root.cameraName
            if (typeof frigateRef.getRecordingsForCamera === "function") {
                var segs = frigateRef.getRecordingsForCamera(id)
                if (segs && segs.length > 0) {
                    applyRecordings(segs)
                    stop()
                    return
                }
            }
            if (tries >= 15)
                stop()
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        z: 20
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape && root.closeEnabled) {
                root.requestClose()
                event.accepted = true
            }
        }
    }

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bottomEdge.top
        z: 15
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: if (root.closeEnabled) root.requestClose()
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
                text: "LIVE"
                color: "#00C853"
                font.pixelSize: 13
            }
            Text {
                text: root.mainReady ? "MAIN" : "SUB"
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
            onClicked: root.requestClose()
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
        onLoaded: applyTimelineCamera()
    }

    MouseArea {
        id: bottomEdge
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 56
        z: 60
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onEntered: {
            showTimelineBar()
            timelineHideTimer.stop()
        }
        onExited: timelineHideTimer.restart()
        onPositionChanged: {
            showTimelineBar()
            timelineHideTimer.restart()
        }
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
        timelineHideTimer.restart()
    }

    function applyRecordings(segments) {
        if (!timelineLoader.item)
            return
        timelineLoader.item.recordings = segments
        if (segments && segments.length > 0) {
            timelineLoader.item.startTs = segments[0].start
            timelineLoader.item.endTs = segments[segments.length - 1].end
            console.log("Timeline UI: applied", segments.length, "blocks for", root.cameraName)
        }
    }

    function applyEvents(list) {
        if (!timelineLoader.item)
            return
        timelineLoader.item.events = list
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
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()
        apiConn.target = frigateRef
        subVideo.queue = subQueue
        mainVideo.queue = mainQueue
        if (mainQueue)
            forceMainTimer.restart()
        else
            forceMainTimer.stop()

        applyTimelineCamera()
        loadTimelineData()
    }

    function close() {
        closeArmTimer.stop()
        forceMainTimer.stop()
        timelineHideTimer.stop()
        recordingsPollTimer.stop()
        closeEnabled = false
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
        subVideo.queue = null
        mainVideo.queue = null

        if (timelineLoader.item) {
            timelineLoader.item.allowAutoReveal = false
            timelineLoader.item.collapsed = true
            timelineLoader.item.cameraId = ""
            timelineLoader.item.cameraName = ""
            timelineLoader.item.recordings = []
            timelineLoader.item.events = []
            timelineLoader.item.startTs = 0
            timelineLoader.item.endTs = 0
        }
    }
}