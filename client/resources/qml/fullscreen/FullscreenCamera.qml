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
    property var liveQueue: null
    property var playbackQueue: null
    property bool isOnline: false

    property bool isPlayback: false
    property int playbackPositionMs: 0

    // Almost instant fade
    opacity: 0.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    FocusScope {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onReleased: {
            if (event.key === Qt.Key_Escape)
                root.close()
            event.accepted = true
        }
    }

    Rectangle {
        id: videoArea
        anchors.fill: parent
        color: "black"

        CameraVideoItem {
            id: liveVideo
            anchors.fill: parent
            visible: !isPlayback && liveQueue !== null
            queue: liveQueue
        }

        CameraVideoItem {
            id: playbackVideo
            anchors.fill: parent
            visible: isPlayback && playbackQueue !== null
            queue: playbackQueue
        }

        Rectangle {
            anchors.fill: parent
            color: "#222"
            visible: liveQueue === null && playbackQueue === null

            Text {
                anchors.centerIn: parent
                text: "No video queue"
                color: "white"
                font.pixelSize: 24
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onDoubleClicked: root.close()
        }
    }

    // Lightweight overlays (appear after window is shown)
    Rectangle {
        id: topOverlay
        height: 36
        width: parent.width
        anchors.top: parent.top
        color: "#00000099"
        opacity: 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 16

            Text {
                text: cameraName
                color: "white"
                font.pixelSize: 15
                font.bold: true
            }

            Text {
                text: isPlayback ? "PLAYBACK" : "LIVE"
                color: isPlayback ? "#FFC107" : "#00C853"
                font.pixelSize: 13
            }
        }
    }

    Rectangle {
        id: exitButton
        width: 70
        height: 28
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        radius: 4
        color: "#000000AA"
        opacity: 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "Exit"
            color: "white"
            font.pixelSize: 13
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Timeline loaded asynchronously and only when needed
    Loader {
        id: timelineLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 90
        asynchronous: true
        active: false          // start inactive
        source: "qrc:/app/resources/qml/fullscreen/FullscreenTimeline.qml"
    }

    function open() {
        // 1. Show window immediately (this is the key for speed)
        visible = true
        showFullScreen()
        opacity = 1.0

        isPlayback = false
        playbackPositionMs = 0

        // 2. Show overlays a tiny bit later
        Qt.callLater(function() {
            topOverlay.opacity = 1.0
            exitButton.opacity = 1.0
        })

        // 3. Heavy work much later
        Qt.callLater(function() {
            // Activate timeline only now
            timelineLoader.active = true

            if (frigateRef && cameraId !== "") {
                frigateRef.loadEvents(cameraId)
                frigateRef.loadRecordings(cameraId)
            }
        })
    }

    function close() {
        opacity = 0.0
        topOverlay.opacity = 0.0
        exitButton.opacity = 0.0

        showNormal()

        Qt.callLater(function() {
            visible = false
            timelineLoader.active = false   // free timeline resources
        })
    }
}