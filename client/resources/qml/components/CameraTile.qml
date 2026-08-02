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

    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""
    property string streamType: ""

    property var frameQueue: null

    property var originalParent: null
    property real originalX: 0
    property real originalY: 0
    property real originalWidth: 0
    property real originalHeight: 0

    property real pressX: 0
    property real pressY: 0
    property bool didReparent: false

    property bool isOnline: cameraName !== "" && frameQueue !== null

    signal removeRequested()

    function bindQueue() {
        if (tile.frigateRef &&
            tile.cameraName !== "" &&
            typeof tile.frigateRef.getQueue === "function") {
            tile.frameQueue = tile.frigateRef.getQueue(tile.cameraName)
        } else {
            tile.frameQueue = null
        }
    }

    onCameraNameChanged: bindQueue()
    Component.onCompleted: bindQueue()

    // NEVER stopStream here — hiding under fullscreen would kill the main stream
    onVisibleChanged: {
        if (visible && cameraName !== "")
            bindQueue()
    }

    Rectangle {
        anchors.fill: parent
        color: "#101010"
        radius: 6
        visible: frameQueue === null
    }

    CameraVideoItem {
        id: videoFrame
        anchors.fill: parent
        queue: frameQueue
        visible: frameQueue !== null
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
        visible: cameraName !== "" && frameQueue === null
        z: 50

        Text {
            anchors.centerIn: parent
            text: "Connecting…"
            color: "#aaaaaa"
            font.pixelSize: 14
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
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        drag.target: dragging ? tile : undefined
        drag.axis: Drag.XAndYAxis

        onPressed: function(mouse) {
            dragging = false
            didReparent = false
            pressX = mouse.x
            pressY = mouse.y
            originalParent = tile.parent
            originalX = tile.x
            originalY = tile.y
            originalWidth = tile.width
            originalHeight = tile.height
        }

        onPositionChanged: function(mouse) {
            if (!pressed)
                return

            var dx = mouse.x - pressX
            var dy = mouse.y - pressY

            if (!dragging && (dx * dx + dy * dy) >= 36) {
                dragging = true
                if (!didReparent && originalParent && gridRoot) {
                    didReparent = true
                    tile.parent = gridRoot
                    tile.width = originalWidth
                    tile.height = originalHeight
                    var p = originalParent.mapToItem(gridRoot, originalX, originalY)
                    tile.x = p.x
                    tile.y = p.y
                }
            }

            if (dragging && gridRoot && gridRoot.updateHoverIndex) {
                var global = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(global.x, global.y, cameraName)
            }
        }

        onReleased: {
            if (dragging) {
                if (didReparent && originalParent) {
                    tile.parent = originalParent
                    tile.x = originalX
                    tile.y = originalY
                    tile.width = originalWidth
                    tile.height = originalHeight
                }
                if (mainWindow && mainWindow.dropHandler) {
                    mainWindow.dropHandler.reorderTile(tileIndex, tile)
                    if (gridRoot && gridRoot.cameraNames && tile.tileIndex >= 0)
                        tile.cameraName = gridRoot.cameraNames[tile.tileIndex]
                }
            }
            dragging = false
            didReparent = false
        }

        onDoubleClicked: {
            if (gridRoot && gridRoot.enterFullscreen && cameraName !== "")
                gridRoot.enterFullscreen(cameraName)
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
                    gridRoot.enterFullscreen(cameraName)
            }
        }

        MenuItem {
            text: "Remove Camera"
            enabled: cameraName !== ""
            onTriggered: tile.handleRemove()
        }
    }

    function handleRemove() {
        if (frigateRef && cameraName !== "" &&
            typeof frigateRef.stopStream === "function") {
            frigateRef.stopStream(cameraName)
        }
        if (gridRoot && gridRoot.removeTile)
            gridRoot.removeTile(tileIndex)
    }
}