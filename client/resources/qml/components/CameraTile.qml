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
        if (tile.frigateRef &&
            tile.cameraName !== "" &&
            typeof tile.frigateRef.getQueue === "function") {

            if (tile.boundCameraName !== tile.cameraName || tile.frameQueue === null) {
                tile.boundCameraName = tile.cameraName
                tile.frameQueue = tile.frigateRef.getQueue(tile.cameraName)
            }
            pullStats()
        } else {
            tile.boundCameraName = ""
            tile.frameQueue = null
            tile.resolution = ""
            tile.fps = 0
            tile.bitrateKbps = 0
            tile.codec = ""
        }
    }

    function pullStats() {
        if (!frigateRef || cameraName === "")
            return
        try {
            if (typeof frigateRef.cameraResolution === "function")
                resolution = frigateRef.cameraResolution(cameraName) || ""
            if (typeof frigateRef.cameraFps === "function")
                fps = frigateRef.cameraFps(cameraName) || 0
            if (typeof frigateRef.cameraBitrateKbps === "function")
                bitrateKbps = frigateRef.cameraBitrateKbps(cameraName) || 0
            if (typeof frigateRef.cameraCodec === "function")
                codec = frigateRef.cameraCodec(cameraName) || ""
        } catch (e) {}
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true
        function onCameraStatsChanged(name, res, f, br, c) {
            if (name !== cameraName)
                return
            resolution = res || ""
            fps = f || 0
            bitrateKbps = br || 0
            codec = c || ""
        }
    }

    Timer {
        interval: 1000
        running: cameraName !== ""
        repeat: true
        onTriggered: pullStats()
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

    // Drag layer — BELOW overlay
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: 100
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: false
        propagateComposedEvents: true

        drag.target: tile
        drag.axis: Drag.XAndYAxis
        drag.threshold: 8

        onPressed: function(mouse) {
            if (mouse.button !== Qt.LeftButton)
                return
            originalX = tile.x
            originalY = tile.y
            tile.anchors.centerIn = undefined
            tile.z = 99999
            if (tile.parent)
                tile.parent.z = 99999
        }

        onPositionChanged: function(mouse) {
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

        onReleased: function(mouse) {
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

        onDoubleClicked: function(mouse) {
            if (gridRoot && gridRoot.enterFullscreen && cameraName !== "")
                gridRoot.enterFullscreen(cameraName)
        }

        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                contextMenu.open()
        }
    }

    // Overlay ABOVE drag — i / x get clicks
    CameraTileOverlay {
        anchors.fill: parent
        z: 300
        visible: cameraName !== ""
        cameraName: tile.cameraName
        resolution: tile.resolution
        fps: tile.fps
        bitrateKbps: tile.bitrateKbps
        codec: tile.codec
        onInfoRequested: {
            console.log("Camera info requested", cameraName)
            console.log("Camera info requested", cameraName)
            infoPopup.open()
        }
        onRemoveRequested: {
            console.log("Camera remove requested", cameraName)
            console.log("Camera remove requested", cameraName)
            tile.handleRemove()
        }
    }

    Popup {
        id: infoPopup
        modal: true
        focus: true
        padding: 0
        width: 280
        height: contentCol.implicitHeight + 24
        x: Math.max(0, (tile.width - width) / 2)
        y: Math.max(0, (tile.height - height) / 2)
        background: Rectangle {
            color: "#1E1E1E"
            radius: 8
            border.color: "#3A3A3A"
            border.width: 1
        }

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            Text {
                text: cameraName !== "" ? cameraName : "Camera"
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }

            Rectangle { width: parent.width; height: 1; color: "#333" }

            Row {
                spacing: 8
                width: parent.width
                Text { text: "Status"; color: "#888"; font.pixelSize: 13; width: 90 }
                Text {
                    text: isOnline ? "Online" : "Offline"
                    color: isOnline ? "#00C853" : "#FF5252"
                    font.pixelSize: 13
                }
            }
            Row {
                spacing: 8
                width: parent.width
                Text { text: "Resolution"; color: "#888"; font.pixelSize: 13; width: 90 }
                Text {
                    text: resolution !== "" ? resolution : "—"
                    color: "white"
                    font.pixelSize: 13
                }
            }
            Row {
                spacing: 8
                width: parent.width
                Text { text: "Codec"; color: "#888"; font.pixelSize: 13; width: 90 }
                Text {
                    text: codec !== "" ? codec.toUpperCase() : "—"
                    color: "white"
                    font.pixelSize: 13
                }
            }
            Row {
                spacing: 8
                width: parent.width
                Text { text: "FPS"; color: "#888"; font.pixelSize: 13; width: 90 }
                Text {
                    text: fps > 0 ? fps.toFixed(1) : "—"
                    color: "white"
                    font.pixelSize: 13
                }
            }
            Row {
                spacing: 8
                width: parent.width
                Text { text: "Bitrate"; color: "#888"; font.pixelSize: 13; width: 90 }
                Text {
                    text: bitrateKbps > 0 ? (bitrateKbps + " kbps") : "—"
                    color: "white"
                    font.pixelSize: 13
                }
            }

            Item { width: 1; height: 4 }

            Button {
                text: "Close"
                width: parent.width
                onClicked: infoPopup.close()
                background: Rectangle {
                    radius: 6
                    color: parent.down ? "#444" : "#2A2A2A"
                }
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
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
            text: "Camera info"
            enabled: cameraName !== ""
            onTriggered: infoPopup.open()
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