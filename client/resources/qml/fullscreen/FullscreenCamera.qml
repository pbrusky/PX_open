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
    property bool _pxOpened: false
    property bool _queuesBound: false

    opacity: 0.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    function updateQueues() {
        if (!frigateRef || cameraName === "")
            return

        // Only bind once per open; parent already passed liveQueue when possible
        if (!_queuesBound) {
            if (!liveQueue)
                liveQueue = frigateRef.getFullscreenQueue(cameraName)
            if (!playbackQueue)
                playbackQueue = frigateRef.getPlaybackQueue(cameraName)
            _queuesBound = true
        }
    }

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
                text: "Connecting…"
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

    Loader {
        id: timelineLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 90
        asynchronous: true
        active: false
        source: "qrc:/app/resources/qml/fullscreen/FullscreenTimeline.qml"
    }

    function open() {
        updateQueues()

        visible = true
        showFullScreen()
        opacity = 1.0

        isPlayback = false
        playbackPositionMs = 0

        Qt.callLater(function() {
            topOverlay.opacity = 1.0
            exitButton.opacity = 1.0
        })

        Qt.callLater(function() {
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

        // Stop main stream so next fullscreen open is clean
        if (frigateRef && cameraName !== "" &&
            typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(cameraName)
        }

        liveQueue = null
        playbackQueue = null
        _queuesBound = false
        _pxOpened = false

        Qt.callLater(function() {
            visible = false
            timelineLoader.active = false
        })
    }

    onClosing: {
        // OS close / Alt+F4
        if (frigateRef && cameraName !== "" &&
            typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(cameraName)
        }
    }
}