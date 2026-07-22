import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"
    z: 10000

    //
    // Injected by CameraGrid / MainWindow
    //
    property var mainWindow: null
    property var discovery: null

    property string cameraId: ""
    property string cameraName: ""
    property var frigateRef: null
    property var liveQueue: null
    property var playbackQueue: null
    property bool isOnline: false

    property bool isPlayback: false
    property int playbackPositionMs: 0

    opacity: 0.0
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Rectangle {
        id: videoArea
        anchors.fill: parent
        color: "black"

        CameraVideoItem {
            id: liveVideo
            anchors.fill: parent
            visible: isOnline && !isPlayback
            queue: liveQueue
        }

        CameraVideoItem {
            id: playbackVideo
            anchors.fill: parent
            visible: isPlayback
            queue: playbackQueue
        }

        Rectangle {
            anchors.fill: parent
            color: "#222"
            visible: !isOnline && !isPlayback

            Text {
                anchors.centerIn: parent
                text: "Camera Offline"
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

    Keys.onReleased: {
        if (event.key === Qt.Key_Escape)
            root.close()
    }

    Rectangle {
        id: topOverlay
        height: 40
        width: parent.width
        anchors.top: parent.top
        color: "#00000088"
        opacity: 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 20

            Text {
                text: cameraName
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }

            Text {
                text: isOnline ? (isPlayback ? "PLAYBACK" : "LIVE") : "OFFLINE"
                color: isOnline ? (isPlayback ? "#FFC107" : "#00C853") : "#00C853"
                font.pixelSize: 14
            }

            Text {
                id: fpsText
                text: "FPS: --"
                color: "white"
                font.pixelSize: 14
            }

            Text {
                id: resText
                text: "Resolution: --"
                color: "white"
                font.pixelSize: 14
            }
        }
    }

    Rectangle {
        id: exitButton
        width: 80
        height: 32
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 12
        radius: 4
        color: "#000000AA"
        opacity: 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: "Exit"
            color: "white"
            font.pixelSize: 14
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    //
    // ⭐ TIMELINE (NX-style auto-hide)
    //
    Rectangle {
        id: timelineContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 90
        color: "transparent"
        clip: true

        Loader {
            id: timelineLoader
            anchors.fill: parent
            source: "qrc:/app/resources/qml/FullscreenTimeline.qml"

            onLoaded: {
                if (!timelineLoader.item)
                    return

                var t = timelineLoader.item
                t.cameraId = cameraId
                t.cameraName = cameraName
                t.frigateRef = frigateRef

                t.allowAutoReveal = true
                t.collapsed = true
            }
        }
    }

    Rectangle {
        id: bottomNameOverlay
        width: parent.width
        height: 40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        color: "#00000088"
        opacity: root.opacity
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: cameraName
            color: "white"
            font.pixelSize: 20
            font.bold: true
        }
    }

    Rectangle {
        id: liveButton
        width: 100
        height: 32
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 12
        radius: 4
        color: "#000000AA"
        visible: isPlayback
        opacity: isPlayback ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: "LIVE"
            color: "white"
            font.pixelSize: 14
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!cameraId || cameraId === "")
                    return

                isPlayback = false
                playbackPositionMs = 0

                if (frigateRef)
                    frigateRef.switchToLive(cameraId)

                if (timelineLoader.item)
                    timelineLoader.item.collapsed = true
            }
        }
    }

    Connections {
        target: frigateRef || null
        ignoreUnknownSignals: true

        function onPlaybackPositionChanged(receivedCameraId, positionMs) {
            if (receivedCameraId !== cameraId)
                return

            playbackPositionMs = positionMs
        }

        function onCameraOnline(id) {
            if (id === cameraId)
                isOnline = true
        }

        function onCameraOffline(id) {
            if (id === cameraId)
                isOnline = false
        }

        function onCameraEditResult(ok, message) {
            if (!ok) return

            if (isPlayback)
                playbackVideo.queue = playbackQueue
            else
                liveVideo.queue = liveQueue
        }
    }

    function open() {
        root.visible = true
        root.opacity = 1.0
        topOverlay.opacity = 1.0
        exitButton.opacity = 1.0

        isPlayback = false
        playbackPositionMs = 0

        if (frigateRef && cameraId && cameraId !== "") {
            frigateRef.loadEvents(cameraId)
            frigateRef.loadRecordings(cameraId)
        }

        if (timelineLoader.item) {
            var t = timelineLoader.item
            t.cameraId = cameraId
            t.cameraName = cameraName
            t.frigateRef = frigateRef
            t.allowAutoReveal = true
            t.collapsed = true
        }
    }

    function close() {
        root.opacity = 0.0
        topOverlay.opacity = 0.0
        exitButton.opacity = 0.0

        Qt.callLater(() => {
            root.visible = false
            root.parent.source = ""
        })
    }
}
