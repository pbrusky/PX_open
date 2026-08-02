import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: gridContainer
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
    property string fullscreenName: ""

    property var cameraOnlineMap: ({})

    function cameraOnline(name) {
        cameraOnlineMap[name] = true
        cameraOnlineMap = cameraOnlineMap
        grid.forceLayout()
    }

    function cameraOffline(name) {
        cameraOnlineMap[name] = false
        cameraOnlineMap = cameraOnlineMap
        grid.forceLayout()
    }

    function getCamera(name) {
        if (!mainWindow || !mainWindow.cameraList)
            return null
        return mainWindow.cameraList.find(function(c) {
            return c.name === name || c.id === name
        })
    }

    function isCameraOnline(name) {
        if (cameraOnlineMap.hasOwnProperty(name))
            return cameraOnlineMap[name]
        return frigateRef ? frigateRef.isCameraOnline(name) : false
    }

    onCameraNamesChanged: updateGridSize()

    function updateGridSize() {
        var count = cameraNames.length
        if (count <= 1) { cols = 1; rows = 1 }
        else if (count <= 2) { cols = 2; rows = 1 }
        else if (count <= 4) { cols = 2; rows = 2 }
        else if (count <= 9) { cols = 3; rows = 3 }
        else {
            var side = Math.ceil(Math.sqrt(count))
            cols = side; rows = side
        }
    }

    function dropAt(x, y, cameraName) {
        if (!cameraName || cameraName === "")
            return
        if (cameraNames.indexOf(cameraName) !== -1)
            return

        cameraNames.push(cameraName)
        cameraNames = cameraNames.slice()
        updateGridSize()

        if (frigateRef && typeof frigateRef.getQueue === "function")
            frigateRef.getQueue(cameraName)

        if (mainWindow)
            mainWindow.selectedCameraId = cameraName
    }

    function removeTile(index) {
        if (index < 0 || index >= cameraNames.length)
            return
        var name = cameraNames[index]
        cameraNames.splice(index, 1)
        cameraNames = cameraNames.slice()
        updateGridSize()
        if (name && frigateRef && typeof frigateRef.stopStream === "function")
            frigateRef.stopStream(name)
        if (name && frigateRef && typeof frigateRef.stopFullscreenStream === "function")
            frigateRef.stopFullscreenStream(name)
    }

    function updateHoverIndex(x, y, cameraName) {
        if (cols <= 0 || rows <= 0)
            return
        var col = Math.floor(x / (grid.width / cols))
        var row = Math.floor(y / (grid.height / rows))
        var idx = row * cols + col
        hoverIndex = (idx >= 0 && idx < cameraNames.length) ? idx : -1
        hoverCameraName = cameraName
    }

    function reorderTilesByTileCenter(oldIndex, tileObj) {
        if (hoverIndex < 0 || hoverIndex >= cameraNames.length || hoverIndex === oldIndex)
            return
        var arr = cameraNames.slice()
        var tmp = arr[oldIndex]
        arr[oldIndex] = arr[hoverIndex]
        arr[hoverIndex] = tmp
        cameraNames = arr
        hoverIndex = -1
        if (tileObj) {
            tileObj.tileIndex = arr.indexOf(tileObj.cameraName)
            if (tileObj.tileIndex >= 0)
                tileObj.cameraName = cameraNames[tileObj.tileIndex]
        }
    }

    function enterFullscreen(cameraName) {
        if (!cameraName || cameraName === "")
            return

        console.log("enterFullscreen called for:", cameraName)

        var prevName = fullscreenName

        var instantQueue = null
        if (frigateRef && typeof frigateRef.getQueue === "function")
            instantQueue = frigateRef.getQueue(cameraName)

        fullscreenName = cameraName
        fullscreenCamera = getCamera(cameraName) || { id: cameraName, name: cameraName }
        fullscreenLiveQueue = instantQueue

        // Reparent overlay to the whole application window
        if (mainWindow && mainWindow.contentItem) {
            fullscreenLoader.parent = mainWindow.contentItem
            fullscreenLoader.anchors.fill = mainWindow.contentItem
        } else {
            fullscreenLoader.parent = gridContainer
            fullscreenLoader.anchors.fill = gridContainer
        }
        fullscreenLoader.z = 1000000
        fullscreenLoader.visible = true

        if (fullscreenLoader.source.toString().indexOf("FullscreenCamera.qml") < 0)
            fullscreenLoader.source = "qrc:/app/resources/qml/fullscreen/FullscreenCamera.qml"
        else if (fullscreenLoader.item)
            applyFullscreenItem(cameraName, instantQueue)

        // Stop previous main only after switch
        if (prevName !== "" && prevName !== cameraName &&
            frigateRef && typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(prevName)
        }

        Qt.callLater(function() {
            if (!frigateRef || fullscreenName !== cameraName)
                return
            if (typeof frigateRef.getFullscreenQueue !== "function")
                return
            var primary = frigateRef.getFullscreenQueue(cameraName)
            if (primary && fullscreenName === cameraName) {
                fullscreenLiveQueue = primary
                if (fullscreenLoader.item)
                    fullscreenLoader.item.liveQueue = primary
            }
        })
    }

    function applyFullscreenItem(cameraName, queue) {
        var item = fullscreenLoader.item
        if (!item)
            return

        item.cameraId = cameraName
        item.cameraName = cameraName
        item.frigateRef = frigateRef
        item.isOnline = true
        item.liveQueue = queue
        item._pxOpened = true
        item._queuesBound = true

        try {
            item.requestClose.disconnect(gridContainer.exitFullscreen)
        } catch (e) {}
        item.requestClose.connect(gridContainer.exitFullscreen)

        console.log("Opening fullscreen for", cameraName)
        item.open()
    }

    function exitFullscreen() {
        var name = fullscreenName

        if (fullscreenLoader.item)
            fullscreenLoader.item.close()

        fullscreenLoader.visible = false
        fullscreenLoader.parent = gridContainer
        fullscreenName = ""
        fullscreenCamera = null
        fullscreenLiveQueue = null

        if (name !== "" && frigateRef &&
            typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(name)
        }
    }

    function addCamera() {
        if (serverViewRoot && serverViewRoot.openAddCameraPopup)
            serverViewRoot.openAddCameraPopup()
    }

    function removeCamera(cameraId) {
        if (serverViewRoot && serverViewRoot.openRemoveCameraPopup)
            serverViewRoot.openRemoveCameraPopup(cameraId)
    }

    Grid {
        id: grid
        anchors.fill: parent
        columns: gridContainer.cols
        rowSpacing: 6
        columnSpacing: 6

        Repeater {
            model: gridContainer.cameraNames

            delegate: Item {
                property string cameraName: modelData
                property real cellW: (grid.width / Math.max(gridContainer.cols, 1)) - grid.columnSpacing
                property real cellH: (grid.height / Math.max(gridContainer.rows, 1)) - grid.rowSpacing
                width: Math.min(cellW, cellH * 16 / 9)
                height: Math.min(cellH, cellW * 9 / 16)

                CameraTile {
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    cameraName: parent.cameraName
                    gridRoot: gridContainer
                    frigateRef: gridContainer.frigateRef
                    mainWindow: gridContainer.mainWindow
                    tileIndex: index
                    onRemoveRequested: gridContainer.removeTile(index)
                }
            }
        }
    }

    Loader {
        id: fullscreenLoader
        anchors.fill: parent
        visible: false
        z: 99999
        asynchronous: false
        onLoaded: {
            if (fullscreenName !== "")
                applyFullscreenItem(fullscreenName, fullscreenLiveQueue)
        }
    }

    Component.onCompleted: updateGridSize()
}