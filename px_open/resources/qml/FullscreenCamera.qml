import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0
import "components/timeline"

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"

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
                text: isOnline ? "LIVE" : "OFFLINE"
                color: isOnline ? "#00C853" : "#FF4444"
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

    // Timeline container with clipping
    Rectangle {
        id: timelineContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: timelineLoader.item ? timelineLoader.item.timelineHeight : 0
        color: "transparent"
        clip: true

        Loader {
            id: timelineLoader
            anchors.fill: parent
            source: "qrc:/app/resources/qml/FullscreenTimeline.qml"

            onLoaded: {
                if (!item || !frigateRef)
                    return

                item.frigateRef = frigateRef
                item.cameraId = cameraId
                item.cameraName = cameraName || cameraId

                if (cameraId && cameraId !== "") {
                    frigateRef.loadEvents(cameraId)
                    frigateRef.loadRecordings(cameraId)
                }
            }
        }
    }

    Rectangle {
        id: bottomNameOverlay
        width: parent.width
        height: 40
        anchors.bottom: timelineContainer.top
        anchors.bottomMargin: 14
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
            }
        }
    }

    TimelineAutoHide {
        id: timelineAutoHide
        timeline: timelineLoader.item
        scrubber: timelineLoader.item ? timelineLoader.item.scrubber : null
        mouseHandler: timelineLoader.item ? timelineLoader.item.mouseHandler : null
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onPlaybackPositionChanged(receivedCameraId, positionMs) {
            if (receivedCameraId !== cameraId)
                return

            playbackPositionMs = positionMs
            isPlayback = true

            if (timelineLoader.item && timelineLoader.item.timestampToRatio) {
                timelineLoader.item.position =
                    timelineLoader.item.timestampToRatio(positionMs)
            }
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

        if (frigateRef && cameraId && cameraId !== "") {
            frigateRef.loadEvents(cameraId)
            frigateRef.loadRecordings(cameraId)
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
