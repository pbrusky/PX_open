import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15
import PxOpen 1.0

Window {
    id: root
    visible: false
    color: "black"
    flags: Qt.FramelessWindowHint | Qt.Window

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

    onSubQueueChanged: subVideo.queue = subQueue
    onMainQueueChanged: {
        mainReady = false
        mainVideo.queue = mainQueue
        if (mainQueue)
            mainPoll.restart()
        else
            mainPoll.stop()
    }

    Rectangle { anchors.fill: parent; color: "black" }

    CameraVideoItem {
        id: subVideo
        anchors.fill: parent
        z: 0
        visible: subQueue !== null
        queue: subQueue
    }

    CameraVideoItem {
        id: mainVideo
        anchors.fill: parent
        z: 1
        visible: mainReady && mainQueue !== null
        queue: mainQueue
    }

    Timer {
        id: mainPoll
        interval: 150
        repeat: true
        running: false
        onTriggered: {
            if (!mainQueue) { stop(); return }
            var ok = false
            try { ok = mainQueue.hasFrames() } catch (e) { stop(); return }
            if (ok) {
                mainReady = true
                console.log("Fullscreen: MAIN layer ON for", cameraName)
                stop()
            }
        }
    }

    Timer {
        id: closeArmTimer
        interval: 800
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
            Text { text: root.cameraName; color: "white"; font.pixelSize: 15; font.bold: true }
            Text { text: "LIVE"; color: "#00C853"; font.pixelSize: 13 }
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
        Text { anchors.centerIn: parent; text: "Exit"; color: "white"; font.pixelSize: 13 }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.closeEnabled)
                    root.requestClose()
            }
        }
    }

    function open() {
        closeEnabled = false
        mainReady = false
        visible = true
        showFullScreen()
        raise()
        requestActivate()
        forceActiveFocus()
        closeArmTimer.restart()
        if (mainQueue)
            mainPoll.restart()
    }

    function close() {
        mainPoll.stop()
        closeArmTimer.stop()
        closeEnabled = false
        showNormal()
        visible = false
        mainReady = false
        subQueue = null
        mainQueue = null
    }

    onClosing: {
        if (frigateRef && cameraName !== "" &&
            typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(cameraName)
        }
    }
}