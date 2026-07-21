import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: gridContainer
    anchors.fill: parent
    clip: false
    z: 1

    property var mainWindow
    property var frigateRef: null
    property var cameraList: []
    property var serverViewRoot

    property var cameraNames: []
    property int cols: 2
    property int rows: 2

    property int hoverIndex: -1
    property string hoverCameraName: ""

    property var fullscreenCamera: null
    property var fullscreenLiveQueue: null
    property var fullscreenPlaybackQueue: null

    onCameraNamesChanged: updateGridSize()

    function getCamera(name) {
        if (!mainWindow || !mainWindow.cameraList)
            return null
        return mainWindow.cameraList.find(c => c.name === name)
    }

    function isCameraOnline(name) {
        return frigateRef ? frigateRef.isCameraOnline(name) : false
    }

    function updateGridSize() {
        let count = cameraNames.length
        if (count <= 1) {
            cols = 1; rows = 1
        } else if (count <= 2) {
            cols = 2; rows = 1
        } else if (count <= 4) {
            cols = 2; rows = 2
        } else if (count <= 9) {
            cols = 3; rows = 3
        } else {
            let side = Math.ceil(Math.sqrt(count))
            cols = side
            rows = side
        }
    }

    function dropAt(x, y, cameraName) {
        if (!cameraName || cameraName === "") return
        if (cameraNames.indexOf(cameraName) !== -1) return

        console.log("Dropping camera:", cameraName)

        cameraNames.push(cameraName)
        cameraNames = cameraNames.slice()

        updateGridSize()

        if (mainWindow && mainWindow.selectedCameraId !== cameraName)
            mainWindow.selectedCameraId = cameraName
    }

    function removeCamera(cameraName) {
        cameraNames = cameraNames.filter(n => n !== cameraName)
        updateGridSize()
    }

    function removeTile(index) {
        if (index < 0 || index >= cameraNames.length) return
        cameraNames.splice(index, 1)
        cameraNames = cameraNames.slice()
        updateGridSize()
    }

    function updateHoverIndex(x, y, cameraName) {
        if (cols <= 0 || rows <= 0) return

        let cellW = grid.width / cols
        let cellH = grid.height / rows

        let col = Math.floor(x / cellW)
        let row = Math.floor(y / cellH)
        let idx = row * cols + col

        hoverIndex = (idx >= 0 && idx < cameraNames.length) ? idx : -1
        hoverCameraName = cameraName
    }

    function reorderTilesByTileCenter(oldIndex, tileObj) {
        if (hoverIndex < 0 || hoverIndex >= cameraNames.length || hoverIndex === oldIndex)
            return

        let arr = cameraNames.slice()
        let tmp = arr[oldIndex]
        arr[oldIndex] = arr[hoverIndex]
        arr[hoverIndex] = tmp

        cameraNames = arr
        hoverIndex = -1
        hoverCameraName = ""
    }

    //
    // ⭐ FULLSCREEN FIX — use dedicated queues
    //
    function enterFullscreen(cameraName, liveQueue) {
        let cam = getCamera(cameraName)
        if (!cam) return

        fullscreenCamera = cam

        // ⭐ DO NOT USE liveQueue (shared with grid)
        fullscreenLiveQueue = frigateRef ? frigateRef.getQueue(cameraName) : null
        fullscreenPlaybackQueue = frigateRef ? frigateRef.getPlaybackQueue(cameraName) : null

        fullscreenLoader.source = "qrc:/app/resources/qml/FullscreenCamera.qml"
        fullscreenLoader.visible = true
    }

    function exitFullscreen() {
        fullscreenLoader.visible = false
        fullscreenLoader.source = ""
        fullscreenCamera = null
        fullscreenLiveQueue = null
        fullscreenPlaybackQueue = null
    }

    Grid {
        id: grid
        anchors.fill: parent
        clip: false
        columns: gridContainer.cols
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: gridContainer.cameraNames

            delegate: Item {
                id: tileWrapper
                z: index

                property string cameraName: modelData
                property bool isOnline: gridContainer.isCameraOnline(cameraName)

                property real cellW: grid.width / gridContainer.cols - grid.columnSpacing
                property real cellH: grid.height / gridContainer.rows - grid.rowSpacing

                width:  Math.min(cellW, cellH * 16 / 9)
                height: Math.min(cellH, cellW * 9 / 16)

                CameraTile {
                    id: tile
                    width: parent.width
                    height: parent.height
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2

                    cameraName: tileWrapper.cameraName
                    isOnline: tileWrapper.isOnline

                    gridRoot: gridContainer
                    frigateRef: gridContainer.frigateRef
                    mainWindow: gridContainer.mainWindow
                    tileIndex: index

                    Component.onCompleted: refreshQueue()
                    onCameraNameChanged: refreshQueue()

                    function refreshQueue() {
                        if (frigateRef && cameraName !== "")
                            frameQueue = frigateRef.getQueue(cameraName)
                        else
                            frameQueue = null
                    }

                    onRemoveRequested: gridContainer.removeTile(tileIndex)
                }
            }
        }
    }

    Loader {
        id: fullscreenLoader
        anchors.fill: parent
        visible: false
        z: 9999

        onLoaded: {
            if (!item || !fullscreenCamera) return
            item.cameraId = fullscreenCamera.id || fullscreenCamera.name
            item.cameraName = fullscreenCamera.name || fullscreenCamera.id
            item.frigateRef = gridContainer.frigateRef
            item.isOnline = gridContainer.frigateRef ? gridContainer.frigateRef.isCameraOnline(item.cameraName) : false
            item.liveQueue = gridContainer.fullscreenLiveQueue
            item.playbackQueue = gridContainer.fullscreenPlaybackQueue
            if (item.open) item.open()
        }

        Keys.onEscapePressed: gridContainer.exitFullscreen()
    }

    Component.onCompleted: updateGridSize()
}
