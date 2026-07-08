import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 6.5

Item {
    id: tile
    z: 5

    // wired from CameraGrid
    property var mainWindow
    property var gridRoot
    property var frigateRef

    property string cameraName: ""
    property bool isOnline: false

    property bool selected: false
    property bool isHovered: false

    property bool dragging: false
    property int dragIndex: -1
    property int tileIndex: -1

    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""
    property string streamType: ""

    signal removeRequested()

    //
    // Camera lookup
    //
    function cameraObject() {
        if (!mainWindow || !mainWindow.cameraList)
            return null
        return mainWindow.cameraList.find(c => c.name === cameraName)
    }

    //
    // Stream loading
    //
    onCameraNameChanged: {
        if (!cameraName || cameraName === "") {
            player.source = ""
            return
        }

        let cam = cameraObject()
        if (!cam) {
            player.source = ""
            return
        }

        resolution    = cam.resolution    || ""
        fps           = cam.fps           || 0
        bitrateKbps   = cam.bitrateKbps   || 0
        codec         = cam.codec         || ""
        streamType    = cam.streamType    || ""

        if (!isOnline) {
            player.source = ""
            return
        }

        let url = cam.streamUrl || cam.rtspUrl || cam.url
        player.source = url || ""
    }

    Rectangle {
        anchors.fill: parent
        color: "#101010"
        radius: 6
    }

    MediaPlayer {
        id: player
        videoOutput: videoItem
        audioOutput: audioOut
        loops: MediaPlayer.Infinite
    }

    AudioOutput {
        id: audioOut
        muted: true
    }

    VideoOutput {
        id: videoItem
        anchors.fill: parent
        visible: cameraName !== "" && isOnline

        // Prevents VideoOutput from blocking mouse events
        enabled: false
        focus: false
    }

    Rectangle {
        id: offlineOverlay
        anchors.fill: parent
        color: "#000000AA"
        visible: cameraName !== "" && !isOnline
        z: 50

        Column {
            anchors.centerIn: parent
            spacing: 6

            Text { text: "Camera Offline"; color: "white"; font.pixelSize: 18 }
            Text { text: cameraName; color: "#CCCCCC"; font.pixelSize: 14 }
        }
    }

    Rectangle {
        id: nameTag
        width: parent.width
        height: 24
        anchors.bottom: parent.bottom
        color: "#00000088"
        z: 20
        visible: cameraName !== ""

        Text {
            anchors.centerIn: parent
            text: cameraName
            color: "white"
            font.pixelSize: 14
        }
    }

    Rectangle {
        id: statusDot
        width: 10
        height: 10
        radius: 5
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 6

        visible: cameraName !== ""
        color: isOnline ? "#4CAF50" : "#D32F2F"
        z: 20
    }

    Row {
        id: topRightCluster
        spacing: 6
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6

        visible: isHovered && cameraName !== ""
        z: 200

        Rectangle {
            width: 20; height: 20; radius: 10
            color: "#000000AA"
            border.color: "#FFFFFF"
            border.width: 1

            Text { anchors.centerIn: parent; text: "i"; color: "white"; font.pixelSize: 12 }

            MouseArea {
                anchors.fill: parent
                onClicked: infoOverlay.visible = !infoOverlay.visible
            }
        }

        Rectangle {
            width: 20; height: 20; radius: 10
            color: "#000000AA"
            border.color: "#FFFFFF"
            border.width: 1

            Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 12 }

            MouseArea {
                anchors.fill: parent
                onClicked: removeRequested()
            }
        }
    }

    Rectangle {
        id: infoOverlay
        visible: false
        width: 120
        height: 80
        radius: 3
        anchors.top: topRightCluster.bottom
        anchors.right: topRightCluster.right
        anchors.margins: 4

        color: "#2E2E2EEE"
        border.color: "#FFFFFF22"
        border.width: 1
        z: 300

        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1

            Text { text: resolution; color: "white"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            Text { text: fps.toFixed(2) + "fps"; color: "white"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            Text { text: (bitrateKbps / 1000).toFixed(2) + "Mbps (" + streamType.charAt(0).toUpperCase() + ")"; color: "white"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            Text { text: codec; color: "white"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
            Text { text: streamType === "main" ? "Hi‑Res" : "Lo‑Res"; color: "white"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight }
        }
    }

    //
    // Unified interaction: hover + fullscreen + drag
    //
    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        drag.target: tile
        drag.axis: Drag.XAndYAxis

        onEntered: tile.isHovered = true
        onExited: tile.isHovered = false

        onDoubleClicked: {
            if (!gridRoot || !gridRoot.enterFullscreen)
                return

            if (!cameraName || cameraName === "")
                return

            gridRoot.enterFullscreen(cameraName)
        }

        onPressed: {
            tile.dragging = true
            tile.dragIndex = tile.tileIndex
        }

        onReleased: {
            tile.dragging = false
            gridRoot.reorderTiles(tile.dragIndex, tile.x, tile.y)
            tile.x = 0
            tile.y = 0
        }
    }
}
