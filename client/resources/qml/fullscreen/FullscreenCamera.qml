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
    property string streamLabel: mainReady ? "MAIN" : "SUB"

    signal requestClose()

    onSubQueueChanged: {
        subVideo.queue = subQueue
    }

    onMainQueueChanged: {
        mainReady = false
        mainVideo.queue = mainQueue
        mainFrameConn.target = mainQueue
        if (mainQueue)
            forceMainTimer.restart()
        else
            forceMainTimer.stop()
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
        opacity: mainReady ? 1 : 0
        queue: mainQueue
    }

    Connections {
        id: mainFrameConn
        target: null
        ignoreUnknownSignals: true

        function onFrameReady() {
            if (mainReady)
                return
            mainReady = true
            forceMainTimer.stop()
            console.log("Fullscreen: SUB → MAIN for", cameraName, "(frameReady)")
        }
    }

    // Keep polling until MAIN frames arrive (covers late open + _main→base fallback)
    Timer {
        id: forceMainTimer
        interval: 400
        repeat: true
        onTriggered: {
            if (mainReady || !mainQueue) {
                stop()
                return
            }
            var ok = false
            try { ok = mainQueue.hasFrames() } catch (e) {}
            if (ok) {
                mainReady = true
                stop()
                console.log("Fullscreen: SUB → MAIN for", cameraName, "(timer)")
            }
        }
    }

    Timer {
        id: closeArmTimer
        interval: 1200
        onTriggered: {
            root.closeEnabled = true
            console.log("Fullscreen close armed")
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        z: 20
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape && root.closeEnabled) {
                console.log("Fullscreen ESC exit")
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
            if (root.closeEnabled) {
                console.log("Fullscreen double-click exit")
                root.requestClose()
            }
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
                text: root.streamLabel
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
            onClicked: {
                console.log("Fullscreen Exit button")
                root.requestClose()
            }
        }
    }

    function open() {
        closeEnabled = false
        mainReady = false
        visible = true
        forceActiveFocus()
        closeArmTimer.restart()
        if (mainQueue) {
            mainFrameConn.target = mainQueue
            forceMainTimer.restart()
        }
    }

    function close() {
        forceMainTimer.stop()
        closeArmTimer.stop()
        mainFrameConn.target = null
        closeEnabled = false
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
        subVideo.queue = null
        mainVideo.queue = null
    }
}