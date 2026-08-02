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
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

        drag.target: tile
        drag.axis: Drag.XAndYAxis
        drag.threshold: 8

        onPressed: function(mouse) {
            if (mouse.button !== Qt.LeftButton)
                return

            dragging = false

            // Clear anchors so x/y can change (critical for drag)
            tile.anchors.centerIn = undefined
            tile.anchors.horizontalCenter = undefined
            tile.anchors.verticalCenter = undefined
            tile.anchors.fill = undefined

            originalParent = tile.parent
            originalX = tile.x
            originalY = tile.y
            originalWidth = tile.width
            originalHeight = tile.height

            if (gridRoot && originalParent) {
                var mapped = originalParent.mapToItem(gridRoot, tile.x, tile.y)
                tile.parent = gridRoot
                tile.x = mapped.x
                tile.y = mapped.y
                tile.width = originalWidth
                tile.height = originalHeight
                tile.z = 99999
            }
        }

        onPositionChanged: {
            if (!drag.active)
                return

            dragging = true

            if (gridRoot && gridRoot.updateHoverIndex) {
                var g = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(g.x, g.y, cameraName)
            }
        }

        onReleased: {
            dragging = false
            tile.z = 0

            if (originalParent) {
                tile.parent = originalParent
                tile.x = originalX
                tile.y = originalY
                tile.width = originalWidth
                tile.height = originalHeight
            }

            if (mainWindow && mainWindow.dropHandler && dragArea.drag.active === false) {
                // Always try reorder if we moved
            }
            if (mainWindow && mainWindow.dropHandler) {
                mainWindow.dropHandler.reorderTile(tileIndex, tile)
                if (gridRoot && gridRoot.cameraNames &&
                    tile.tileIndex >= 0 &&
                    tile.tileIndex < gridRoot.cameraNames.length) {
                    tile.cameraName = gridRoot.cameraNames[tile.tileIndex]
                }
            }

            // Restore centered layout inside cell
            tile.anchors.centerIn = originalParent ? originalParent : undefined
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
            typeof frigateRef.stopStream === "function")
            frigateRef.stopStream(cameraName)
        if (gridRoot && gridRoot.removeTile)
            gridRoot.removeTile(tileIndex)
    }
}