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

    onSubQueueChanged: {
        subVideo.queue = subQueue
    }

    onMainQueueChanged: {
        mainReady = false
        mainVideo.queue = mainQueue
    }

    onFrigateRefChanged: {
        apiConn.target = frigateRef
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        visible: true
        opacity: 1
        queue: subQueue
    }

    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        visible: true
        opacity: mainReady ? 1.0 : 0.01
        queue: mainQueue
    }

    Connections {
        id: apiConn
        target: frigateRef
        ignoreUnknownSignals: true

        function onFullscreenFrameReady(name) {
            if (name === root.cameraName)
                root.mainReady = true
        }

        function onFullscreenUsingSub(name) {
            if (name === root.cameraName)
                root.mainReady = false
        }
    }

    Timer {
        id: forceMainTimer
        interval: 200
        repeat: true
        running: root.visible && !root.mainReady && root.mainQueue !== null
        onTriggered: {
            if (mainVideo.hasFrame) {
                root.mainReady = true
                return
            }
            if (root.mainQueue) {
                var ok = false
                try {
                    if (root.mainQueue.hasReceivedFrames)
                        ok = root.mainQueue.hasReceivedFrames()
                } catch (e1) {}
                try {
                    if (!ok && root.mainQueue.hasFrames)
                        ok = root.mainQueue.hasFrames()
                } catch (e2) {}
                if (ok)
                    root.mainReady = true
            }
        }
    }

    Timer {
        id: closeArmTimer
        interval: 1200
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
        onDoubleClicked: {
            if (root.closeEnabled)
                root.requestClose()
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

    function open() {
        closeEnabled = false
        mainReady = false
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()
        apiConn.target = frigateRef
    }

    function close() {
        closeArmTimer.stop()
        closeEnabled = false
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
        subVideo.queue = null
        mainVideo.queue = null
    }
}