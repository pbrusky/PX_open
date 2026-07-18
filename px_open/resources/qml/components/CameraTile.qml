import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0
import "qrc:/app/resources/qml/components"

Item {
    id: tile
    z: 5

    property bool dragging: false
    property int dragIndex: -1
    property int tileIndex: -1

    property var mainWindow
    property var gridRoot
    property var frigateRef

    property string cameraName: ""
    property bool isOnline: frigateRef ? frigateRef.isCameraOnline(cameraName) : false

    // ❌ no direct worker reference
    // property var worker: frigateRef ? frigateRef.getWorker(cameraName) : null

    // simple metadata placeholders (can be filled from backend later)
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

    function handleRemove() {
        if (gridRoot && gridRoot.removeTile)
            gridRoot.removeTile(tileIndex)

        if (frigateRef)
            frigateRef.stopStream(cameraName)
    }

    onCameraNameChanged: {
        if (!cameraName) {
            frameQueue = null
            currentFrame = null
            return
        }

        frameQueue = frigateRef ? frigateRef.getQueue(cameraName) : null
        // worker     = frigateRef ? frigateRef.getWorker(cameraName) : null
    }

    // ❌ remove Connections to worker (cross-thread)
    // Connections {
    //     target: worker
    //     ignoreUnknownSignals: true
    //
    //     function onStatsChanged() {
    //         // bindings auto-update
    //     }
    // }

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
}
