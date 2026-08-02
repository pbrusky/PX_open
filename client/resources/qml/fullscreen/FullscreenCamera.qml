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

    property var liveQueue: null
    property var playbackQueue: null

    property bool isOnline: false
    property bool isPlayback: false
    property int playbackPositionMs: 0
    property bool _pxOpened: false
    property bool _queuesBound: false

    // Notify parent when user requests close
    signal requestClose()

    onLiveQueueChanged: {
        liveVideo.queue = liveQueue
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    FocusScope {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.requestClose()
                event.accepted = true
            }
        }
    }

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
        visible: liveQueue === null && !isPlayback
        z: 1

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
        z: 2
        onDoubleClicked: root.requestClose()
    }

    Rectangle {
        id: topOverlay
        height: 36
        width: parent.width
        anchors.top: parent.top
        color: "#00000099"
        z: 10

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
        z: 11

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
        height: 90
        z: 12
        asynchronous: true
        active: false
        source: "qrc:/app/resources/qml/fullscreen/FullscreenTimeline.qml"
    }

    function open() {
        visible = true
        isPlayback = false
        playbackPositionMs = 0
        keyHandler.forceActiveFocus()

        Qt.callLater(function() {
            timelineLoader.active = true
            if (frigateRef && cameraId !== "") {
                frigateRef.loadEvents(cameraId)
                frigateRef.loadRecordings(cameraId)
            }
        })
    }

    function close() {
        visible = false
        timelineLoader.active = false
        _pxOpened = false
        _queuesBound = false
        // Parent stops the fullscreen stream — do not stop here
        liveQueue = null
        playbackQueue = null
    }
}