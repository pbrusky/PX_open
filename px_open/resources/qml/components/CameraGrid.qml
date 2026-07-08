import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: gridContainer
    anchors.fill: parent
    clip: true
    z: 1
    
    // Provided by ServerView
    property var mainWindow
    property var frigateRef: null

    property var cameraNames: []
    property int cols: 0
    property int rows: 0

    // Camera selected for fullscreen
    property var fullscreenCamera: null

    //
    // Safe camera lookup
    //
    function getCamera(name) {
        if (!mainWindow || !mainWindow.cameraList) {
            console.log("CameraGrid: mainWindow or cameraList undefined")
            return null
        }
        return mainWindow.cameraList.find(c => c.name === name)
    }

    function isCameraOnline(name) {
        let cam = getCamera(name)
        return cam ? !!cam.isOnline : false
    }

    //
    // Grid sizing
    //
    function updateGridSize() {
        let count = cameraNames.length

        if (count <= 0) {
            cols = 0; rows = 0
        } else if (count === 1) {
            cols = 1; rows = 1
        } else if (count === 2) {
            cols = 2; rows = 1
        } else if (count <= 4) {
            cols = 2; rows = 2
        } else if (count <= 9) {
            cols = 3; rows = 3
        } else if (count <= 16) {
            cols = 4; rows = 4
        } else {
            let side = Math.ceil(Math.sqrt(count))
            cols = side
            rows = side
        }
    }

    //
    // Drag & Drop
    //
    function dropAt(x, y, cameraName) {
        if (!cameraName || cameraName === "")
            return

        if (cameraNames.indexOf(cameraName) !== -1)
            return

        cameraNames.push(cameraName)
        updateGridSize()

        if (mainWindow && mainWindow.selectedCameraId !== cameraName) {
            mainWindow.selectedCameraId = cameraName
        }
    }

    function removeCamera(cameraName) {
        cameraNames = cameraNames.filter(function(n) { return n !== cameraName })
        updateGridSize()
    }

    function reorderTiles(oldIndex, x, y) {
        if (oldIndex < 0 || oldIndex >= cameraNames.length)
            return

        let col = Math.floor(x / (grid.width / cols))
        let row = Math.floor(y / (grid.height / rows))
        let newIndex = row * cols + col

        if (newIndex < 0 || newIndex >= cameraNames.length)
            return

        let name = cameraNames[oldIndex]
        cameraNames.splice(oldIndex, 1)
        cameraNames.splice(newIndex, 0, name)
    }

    //
    // Fullscreen
    //
    function enterFullscreen(cameraName) {
        let cam = getCamera(cameraName)
        if (!cam)
            return

        fullscreenCamera = cam
        fullscreenLoader.source = "qrc:/app/resources/qml/FullscreenCamera.qml"
        fullscreenLoader.visible = true
    }

    function exitFullscreen() {
        fullscreenLoader.visible = false
        fullscreenLoader.source = ""
        fullscreenCamera = null
    }

    //
    // Grid layout
    //
    Grid {
        id: grid
        anchors.fill: parent

        columns: gridContainer.cols
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            id: gridRepeater
            model: gridContainer.cols * gridContainer.rows

            Item {
                id: tileWrapper

                width: gridContainer.cols > 0
                       ? grid.width / gridContainer.cols - grid.columnSpacing
                       : 0
                height: gridContainer.rows > 0
                        ? grid.height / gridContainer.rows - grid.rowSpacing
                        : 0

                property string cameraName: (
                    index < gridContainer.cameraNames.length
                    ? gridContainer.cameraNames[index]
                    : ""
                )

                property bool isOnline: cameraName !== ""
                                       ? gridContainer.isCameraOnline(cameraName)
                                       : false

                CameraTile {
                    id: tile
                    anchors.fill: parent
                    z: 1

                    cameraName: tileWrapper.cameraName
                    isOnline: tileWrapper.isOnline

                    gridRoot: gridContainer
                    frigateRef: gridContainer.frigateRef
                    mainWindow: gridContainer.mainWindow
                    tileIndex: index

                    onRemoveRequested: {
                        gridContainer.removeCamera(tileWrapper.cameraName)
                    }
                }
            }
        }
    }

    //
    // Fullscreen Loader
    //
    Loader {
        id: fullscreenLoader
        anchors.fill: parent
        visible: false
        z: 9999

        onLoaded: {
            if (!item || !fullscreenCamera) {
                console.log("FullscreenLoader: no item or no camera")
                return
            }

            item.cameraId = fullscreenCamera.id || fullscreenCamera.name
            item.cameraName = fullscreenCamera.name || fullscreenCamera.id
            item.streamUrl = fullscreenCamera.streamUrl || fullscreenCamera.rtspUrl || fullscreenCamera.url

            item.isOnline = !!fullscreenCamera.isOnline
            item.frigateRef = gridContainer.frigateRef

            if (item.open)
                item.open()
        }

        Keys.onEscapePressed: gridContainer.exitFullscreen()
    }

    Component.onCompleted: {
        cameraNames = []
        updateGridSize()
    }
}
