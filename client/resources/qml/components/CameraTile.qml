import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0

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
    property string boundCameraName: ""

    property real originalX: 0
    property real originalY: 0

    property bool isOnline: cameraName !== "" && frameQueue !== null

    signal removeRequested()

    function bindQueue() {
        if (tile.boundCameraName === tile.cameraName && tile.frameQueue !== null)
            return

        if (tile.frigateRef &&
            tile.cameraName !== "" &&
            typeof tile.frigateRef.getQueue === "function") {
            tile.boundCameraName = tile.cameraName
            tile.frameQueue = tile.frigateRef.getQueue(tile.cameraName)
        } else {
            tile.boundCameraName = ""
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

            tile.anchors.centerIn = undefined
            tile.anchors.horizontalCenter = undefined
            tile.anchors.verticalCenter = undefined
            tile.anchors.fill = undefined

            originalX = tile.x
            originalY = tile.y

            // Tile above siblings inside the cell
            tile.z = 99999

            // Cell above all other grid cells
            if (tile.parent)
                tile.parent.z = 99999
        }

        onPositionChanged: {
            if (!dragArea.drag.active)
                return

            dragging = true

            tile.z = 99999
            if (tile.parent)
                tile.parent.z = 99999

            if (gridRoot && gridRoot.updateHoverIndex) {
                var g = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(g.x, g.y, cameraName)
            }
        }

        onReleased: {
            var didDrag = dragging || dragArea.drag.active
            var fromIndex = tile.tileIndex

            if (didDrag && gridRoot && gridRoot.updateHoverIndex) {
                var g = tile.mapToItem(gridRoot, tile.width / 2, tile.height / 2)
                gridRoot.updateHoverIndex(g.x, g.y, cameraName)
            }

            dragging = false

            tile.z = 0
            if (tile.parent)
                tile.parent.z = 0

            if (didDrag && fromIndex >= 0 && mainWindow && mainWindow.dropHandler)
                mainWindow.dropHandler.reorderTile(fromIndex, tile)

            tile.x = originalX
            tile.y = originalY
            tile.anchors.centerIn = tile.parent

            if (gridRoot)
                gridRoot.hoverIndex = -1
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