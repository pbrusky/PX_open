import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0
import "qrc:/app/resources/qml/components"

Item {
    id: tile
    z: 5

    property bool dragging: false
    property int tileIndex: -1

    property var mainWindow
    property var gridRoot
    property var frigateRef

    property string cameraName: ""
    property bool isOnline: frigateRef ? frigateRef.isCameraOnline(cameraName) : false

    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""
    property string streamType: ""

    property var frameQueue
    property var currentFrame

    signal removeRequested()

    Behavior on x { enabled: !dragging; NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
    Behavior on y { enabled: !dragging; NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    onCameraNameChanged: {
        if (!cameraName) {
            frameQueue = null
            currentFrame = null
            return
        }
        frameQueue = frigateRef ? frigateRef.getQueue(cameraName) : null
    }

    Connections {
        target: frameQueue
        ignoreUnknownSignals: true

        function onFrameReady() {
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
        z: 50
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        propagateComposedEvents: true

        drag.target: tile
        drag.axis: Drag.XAndYAxis

        onPressed: {
            tile.z = 9999
            dragging = true
        }

        onPositionChanged: {
            if (drag.active && gridRoot && gridRoot.updateHoverIndex) {
                var global = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(global.x, global.y, cameraName)
            }
        }

        onReleased: {
            tile.z = 5
            dragging = false

            if (!gridRoot)
                return

            // snap back into its wrapper
            tile.x = (tile.parent.width - tile.width) / 2
            tile.y = (tile.parent.height - tile.height) / 2

            if (gridRoot.reorderTilesByTileCenter)
                gridRoot.reorderTilesByTileCenter(tileIndex, tile)
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
        removeRequested()
    }
}
