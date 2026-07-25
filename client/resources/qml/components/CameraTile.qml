import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0
import "qrc:/app/resources/qml/components"

Item {
    id: tile
    z: dragging ? 99999 : 0

    property bool dragging: false
    property int tileIndex: -1

    property var mainWindow
    property var gridRoot
    property var frigateRef

    property string cameraName: ""

    property bool isOnline: currentFrame !== null && currentFrame !== undefined

    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""
    property string streamType: ""

    property var frameQueue: null
    property var currentFrame

    property var originalParent: null
    property real originalX: 0
    property real originalY: 0
    property real originalWidth: 0
    property real originalHeight: 0

    signal removeRequested()

    onCameraNameChanged: {
        currentFrame = null

        if (frigateRef && cameraName !== "")
            frameQueue = frigateRef.getQueue(cameraName)
        else
            frameQueue = null
    }

    onFrameQueueChanged: {
        frameConn.target = frameQueue

        if (frameQueue) {
            var img = frameQueue.popImage()
            if (img) {
                currentFrame = img
                videoFrame.frame = img
            }
        }
    }

    Connections {
        id: frameConn
        target: frameQueue
        ignoreUnknownSignals: true

        function onFrameReady() {
            if (!frameQueue) return
            var img = frameQueue.popImage()
            if (img) {
                currentFrame = img
                videoFrame.frame = img
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#101010"
        radius: 6
        visible: currentFrame === null || currentFrame === undefined
    }

    FrameItem {
        id: videoFrame
        anchors.fill: parent
        visible: currentFrame !== null && currentFrame !== undefined && isOnline
    }

    Rectangle {
        id: offlineOverlay
        anchors.fill: parent
        color: "#000000AA"
        visible: cameraName !== "" && !isOnline
        z: 50
    }

    CameraTileOverlay {
        id: overlay
        anchors.fill: parent
        z: 100
        visible: cameraName !== ""

        cameraName: tile.cameraName
        resolution: tile.resolution
        fps: tile.fps
        bitrateKbps: tile.bitrateKbps
        codec: tile.codec

        onInfoRequested: infoPopup.open()
        onRemoveRequested: tile.handleRemove()
    }

    Popup {
        id: infoPopup
        modal: true
        focus: true
        width: 260
        height: 180
        background: Rectangle { color: "#222"; radius: 8 }

        Column {
            anchors.centerIn: parent
            spacing: 6
            Text { text: cameraName; color: "white"; font.pixelSize: 18 }
            Text { text: "Resolution: " + resolution; color: "white" }
            Text { text: "Codec: " + codec; color: "white" }
            Text { text: "FPS: " + fps; color: "white" }
            Text { text: "Bitrate: " + bitrateKbps + " kbps"; color: "white" }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        drag.target: tile
        drag.axis: Drag.XAndYAxis

        onPressed: {
            dragging = false

            originalParent = tile.parent
            originalX = tile.x
            originalY = tile.y
            originalWidth = tile.width
            originalHeight = tile.height

            tile.parent = gridRoot
            tile.width = originalWidth
            tile.height = originalHeight
            tile.x = originalParent.mapToItem(gridRoot, originalX, originalY).x
            tile.y = originalParent.mapToItem(gridRoot, originalX, originalY).y
        }

        onPositionChanged: {
            if (!dragging && drag.active)
                dragging = true

            if (dragging && gridRoot && gridRoot.updateHoverIndex) {
                var global = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(global.x, global.y, cameraName)
            }
        }

        onReleased: {
            dragging = false

            if (originalParent) {
                tile.parent = originalParent
                tile.x = originalX
                tile.y = originalY
                tile.width = originalWidth
                tile.height = originalHeight
            }

            if (mainWindow && mainWindow.dropHandler)
                mainWindow.dropHandler.reorderTile(tileIndex, tile)
        }

        onDoubleClicked: {
            if (gridRoot && gridRoot.enterFullscreen && cameraName !== "")
                gridRoot.enterFullscreen(cameraName, frameQueue)
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
            onTriggered: tile.handleRemove()
        }
    }

    function handleRemove() {
        if (mainWindow && mainWindow.dropHandler)
            mainWindow.dropHandler.removeCamera(cameraName)
    }
}
