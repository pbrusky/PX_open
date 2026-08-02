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
    property bool closeEnabled: false

    signal requestClose()

    onLiveQueueChanged: liveVideo.queue = liveQueue

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onReleased: function(event) {
            if (event.key === Qt.Key_Escape && root.closeEnabled) {
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

    Rectangle {
        anchors.fill: parent
        color: "#222"
        visible: liveQueue === null
        z: 1
        Text {
            anchors.centerIn: parent
            text: "Connecting…"
            color: "white"
            font.pixelSize: 24
            font.bold: true
        }
    }

    // Ignore the double-click that opened us
    Timer {
        id: closeArmTimer
        interval: 450
        onTriggered: root.closeEnabled = true
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        z: 2
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
                text: "LIVE"
                color: "#00C853"
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
        z: 11
        Text {
            anchors.centerIn: parent
            text: "Exit"
            color: "white"
            font.pixelSize: 13
        }
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
        visible = true
        isPlayback = false
        closeArmTimer.restart()
    }

    function close() {
        closeArmTimer.stop()
        closeEnabled = false
        visible = false
        liveQueue = null
        playbackQueue = null
        _pxOpened = false
        _queuesBound = false
    }
}