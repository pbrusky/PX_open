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
        anchors.fill: parent
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
                // MAIN = fullscreen HQ stream is showing
                // (main profile when go2rtc has camera_main, else base HQ)
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
    }

    function close() {
        closeArmTimer.stop()
        forceMainTimer.stop()
        closeEnabled = false
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
        subVideo.queue = null
        mainVideo.queue = null
    }
}