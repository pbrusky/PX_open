import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0

Item {
    id: tile
    z: 5

    property var mainWindow
    property var gridRoot
    property var frigateRef

    property string cameraName: ""
    property bool isOnline: frigateRef ? frigateRef.isCameraOnline(cameraName) : false

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

    property var frameQueue
    property var currentFrame

    signal removeRequested()

    function cameraObject() {
        if (!mainWindow || !mainWindow.cameraList)
            return null
        return mainWindow.cameraList.find(c => c.name === cameraName)
    }

    onCameraNameChanged: {
        if (!cameraName || cameraName === "") {
            frameQueue = null
            currentFrame = null
            return
        }

        let cam = cameraObject()
        if (!cam) {
            frameQueue = null
            currentFrame = null
            return
        }

        resolution    = cam.resolution    || ""
        fps           = cam.fps           || 0
        bitrateKbps   = cam.bitrateKbps   || 0
        codec         = cam.codec         || ""
        streamType    = cam.streamType    || ""

        if (!frigateRef) {
            frameQueue = null
            currentFrame = null
            return
        }

        frameQueue = frigateRef.getQueue(cameraName)
        if (frameQueue)
            console.log("CameraTile: using FrameQueue for", cameraName)
        else
            console.log("CameraTile: no FrameQueue for", cameraName)
    }

    Connections {
        target: frameQueue
        ignoreUnknownSignals: true

        function onFrameReady() {
            if (!frameQueue)
                return

            var img = frameQueue.popImage()
            if (!img)
                return

            currentFrame = img
            videoFrame.frame = img
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#101010"
        radius: 6
        visible: currentFrame === null
    }

    FrameItem {
        id: videoFrame
        anchors.fill: parent
        visible: currentFrame !== null && isOnline
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

    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: tile
        drag.axis: Drag.XAndYAxis

        onEntered: tile.isHovered = true
        onExited: tile.isHovered = false

        onDoubleClicked: {
            if (gridRoot && gridRoot.enterFullscreen && cameraName !== "")
                gridRoot.enterFullscreen(cameraName, frameQueue)
        }

        onPressed: {
            tile.dragging = true
            tile.dragIndex = tile.tileIndex
        }

        onReleased: {
            tile.dragging = false
            if (gridRoot && gridRoot.reorderTiles)
                gridRoot.reorderTiles(tile.dragIndex, tile.x, tile.y)
            tile.x = 0
            tile.y = 0
        }

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                contextMenu.open()
        }
    }

    Menu {
        id: contextMenu
        title: cameraName !== "" ? cameraName : "Camera"

        MenuItem {
            text: "Fullscreen"
            enabled: cameraName !== ""
            onTriggered: {
                if (gridRoot && gridRoot.enterFullscreen)
                    gridRoot.enterFullscreen(cameraName, frameQueue)
            }
        }

        MenuItem {
            text: "Remove Camera"
            enabled: cameraName !== ""
            onTriggered: removeRequested()
        }
    }
}
