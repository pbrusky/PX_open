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
        if (name && frigateRef) {
            if (typeof frigateRef.stopStream === "function")
                frigateRef.stopStream(name)
            if (typeof frigateRef.stopFullscreenStream === "function")
                frigateRef.stopFullscreenStream(name)
        }
    }

    function updateHoverIndex(x, y, cameraName) {
        if (cols <= 0 || rows <= 0 || grid.width <= 0 || grid.height <= 0)
            return
        var col = Math.floor(x / (grid.width / cols))
        var row = Math.floor(y / (grid.height / rows))
        var idx = row * cols + col
        hoverIndex = (idx >= 0 && idx < cameraNames.length) ? idx : -1
        hoverCameraName = cameraName || ""
    }

    function reorderTilesByTileCenter(oldIndex, tileObj) {
        if (hoverIndex < 0 || hoverIndex >= cameraNames.length)
            return
        if (oldIndex < 0 || oldIndex >= cameraNames.length)
            return
        if (hoverIndex === oldIndex)
            return

        var arr = cameraNames.slice()
        var tmp = arr[oldIndex]
        arr[oldIndex] = arr[hoverIndex]
        arr[hoverIndex] = tmp
        cameraNames = arr

        hoverIndex = -1
        hoverCameraName = ""

        if (tileObj) {
            var newIdx = arr.indexOf(tileObj.cameraName)
            if (newIdx >= 0) {
                tileObj.tileIndex = newIdx
            }
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

        // Cover the whole main window
        if (mainWindow && mainWindow.contentItem) {
            fullscreenLoader.parent = mainWindow.contentItem
            fullscreenLoader.anchors.fill = mainWindow.contentItem
        }
        fullscreenLoader.z = 1000000
        fullscreenLoader.visible = true

        if (fullscreenLoader.source.toString().indexOf("FullscreenCamera.qml") < 0) {
            fullscreenLoader.source = "qrc:/app/resources/qml/fullscreen/FullscreenCamera.qml"
        } else if (fullscreenLoader.item) {
            applyFullscreenItem(cameraName, instantQueue)
        }

        if (prevName !== "" && prevName !== cameraName &&
            frigateRef && typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(prevName)
        }

        // Upgrade to main/sub AFTER a short delay so open isn't cancelled
        upgradeTimer.cameraName = cameraName
        upgradeTimer.restart()
    }

    Timer {
        id: upgradeTimer
        interval: 300
        property string cameraName: ""
        onTriggered: {
            if (!frigateRef || fullscreenName !== cameraName)
                return
            if (typeof frigateRef.getFullscreenQueue !== "function")
                return
            var primary = frigateRef.getFullscreenQueue(cameraName)
            if (primary && fullscreenName === cameraName && fullscreenLoader.item)
                fullscreenLoader.item.liveQueue = primary
        }
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

        try { item.requestClose.disconnect(gridContainer.exitFullscreen) } catch (e) {}
        item.requestClose.connect(gridContainer.exitFullscreen)

        console.log("Opening fullscreen for", cameraName)
        item.open()
    }

    function exitFullscreen() {
        var name = fullscreenName
        upgradeTimer.stop()

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

    // Highlight target cell while dragging
    Rectangle {
        id: hoverHighlight
        visible: hoverIndex >= 0 && hoverIndex < cameraNames.length
        color: "#2244AA44"
        border.color: "#4488FF"
        border.width: 2
        radius: 6
        z: 50
        width: grid.width / Math.max(cols, 1) - grid.columnSpacing
        height: grid.height / Math.max(rows, 1) - grid.rowSpacing
        x: grid.x + (hoverIndex % cols) * (width + grid.columnSpacing)
        y: grid.y + Math.floor(hoverIndex / cols) * (height + grid.rowSpacing)
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
                id: cell
                property string cameraName: modelData
                property real cellW: (grid.width / Math.max(gridContainer.cols, 1)) - grid.columnSpacing
                property real cellH: (grid.height / Math.max(gridContainer.rows, 1)) - grid.rowSpacing
                width: Math.min(cellW, cellH * 16 / 9)
                height: Math.min(cellH, cellW * 9 / 16)

                CameraTile {
                    // Position with x/y only — NO anchors.centerIn (breaks drag)
                    x: (parent.width - width) / 2
                    y: (parent.height - height) / 2
                    width: parent.width
                    height: parent.height

                    cameraName: cell.cameraName
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