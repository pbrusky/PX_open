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

    property string fullscreenName: ""
    property var fullscreenSubQueue: null
    property var fullscreenMainQueue: null
    property bool fullscreenLocked: false

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
    function nameAt(i) {
        if (!cameraNames || i < 0 || i >= cameraNames.length)
            return ""
        var n = cameraNames[i]
        if (n === undefined || n === null)
            return ""
        return "" + n
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
        if (!cameraName || cameraNames.indexOf(cameraName) !== -1)
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
        var name = nameAt(index)
        cameraNames.splice(index, 1)
        cameraNames = cameraNames.slice()
        updateGridSize()
        if (name !== "" && frigateRef) {
            if (typeof frigateRef.stopStream === "function")
                frigateRef.stopStream(name)
            if (typeof frigateRef.stopFullscreenStream === "function")
                frigateRef.stopFullscreenStream(name)
        }
    }

    function updateHoverIndex(x, y, cameraName) {
        if (cols <= 0 || rows <= 0 || grid.width <= 0)
            return
        var col = Math.floor(x / (grid.width / cols))
        var row = Math.floor(y / (grid.height / rows))
        var idx = row * cols + col
        hoverIndex = (idx >= 0 && idx < cameraNames.length) ? idx : -1
        hoverCameraName = cameraName || ""
    }

    function reorderTilesByTileCenter(oldIndex, tileObj) {
        if (hoverIndex < 0 || oldIndex < 0 || hoverIndex === oldIndex)
            return
        if (hoverIndex >= cameraNames.length || oldIndex >= cameraNames.length)
            return
        var arr = cameraNames.slice()
        var tmp = arr[oldIndex]
        arr[oldIndex] = arr[hoverIndex]
        arr[hoverIndex] = tmp
        cameraNames = arr
        hoverIndex = -1
        if (tileObj) {
            var n = arr.indexOf(tileObj.cameraName)
            if (n >= 0)
                tileObj.tileIndex = n
        }
    }

    function enterFullscreen(cameraName) {
        if (!cameraName || cameraName === "")
            return

        var prevName = fullscreenName
        if (prevName !== "" && prevName !== cameraName &&
            frigateRef && typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(prevName)
        }

        var subQ = null
        if (frigateRef && typeof frigateRef.getQueue === "function")
            subQ = frigateRef.getQueue(cameraName)

        var mainQ = null
        if (frigateRef && typeof frigateRef.getFullscreenQueue === "function")
            mainQ = frigateRef.getFullscreenQueue(cameraName)

        fullscreenName = cameraName
        fullscreenSubQueue = subQ
        fullscreenMainQueue = mainQ
        fullscreenLocked = true
        unlockTimer.restart()

        if (mainWindow && mainWindow.contentItem) {
            fullscreenLoader.parent = mainWindow.contentItem
            fullscreenLoader.anchors.fill = mainWindow.contentItem
            fullscreenLoader.z = 1000000
        }
        fullscreenLoader.visible = true

        if (fullscreenLoader.source.toString().indexOf("FullscreenCamera.qml") < 0) {
            fullscreenLoader.source = "qrc:/app/resources/qml/fullscreen/FullscreenCamera.qml"
        } else if (fullscreenLoader.item) {
            applyFullscreenItem(cameraName, subQ, mainQ)
        }
    }

    Timer {
        id: unlockTimer
        interval: 400
        onTriggered: {
            gridContainer.fullscreenLocked = false
        }
    }

    function applyFullscreenItem(cameraName, subQ, mainQ) {
        var item = fullscreenLoader.item
        if (!item)
            return

        var name = (cameraName !== undefined && cameraName !== null) ? ("" + cameraName) : ""

        try { item.requestClose.disconnect(gridContainer.exitFullscreen) } catch (e) {}
        item.requestClose.connect(gridContainer.exitFullscreen)

        item.cameraId = name
        item.cameraName = name
        item.frigateRef = frigateRef
        item.subQueue = (subQ !== undefined) ? subQ : null
        item.mainQueue = (mainQ !== undefined) ? mainQ : null
        item.mainReady = false

        item.open()
    }

    function exitFullscreen() {
        if (fullscreenLocked)
            return

        var name = fullscreenName
        if (fullscreenLoader.item)
            fullscreenLoader.item.close()

        fullscreenLoader.visible = false
        fullscreenLoader.z = 99999
        fullscreenLoader.anchors.fill = undefined
        fullscreenLoader.parent = gridContainer
        fullscreenLoader.anchors.fill = gridContainer

        fullscreenName = ""
        fullscreenSubQueue = null
        fullscreenMainQueue = null

        if (name !== "" && frigateRef &&
            typeof frigateRef.stopFullscreenStream === "function") {
            frigateRef.stopFullscreenStream(name)
        }

        if (mainWindow) {
            if (typeof mainWindow.enterTrueFullscreen === "function")
                mainWindow.enterTrueFullscreen()
            else if (typeof mainWindow.showFullScreen === "function")
                mainWindow.showFullScreen()
        }
    }

    function openEditCamera(id) {
        if (serverViewRoot && serverViewRoot.openEditCameraPopup)
            serverViewRoot.openEditCameraPopup(id)
    }
    function openRemoveCamera(id) {
        if (serverViewRoot && serverViewRoot.openRemoveCameraPopup)
            serverViewRoot.openRemoveCameraPopup(id)
    }

    Rectangle {
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
        opacity: fullscreenName !== "" ? 0 : 1
        clip: false

        Repeater {
            model: gridContainer.cameraNames.length

            delegate: Item {
                id: cell
                clip: false
                z: 0

                width: {
                    var cellW = (grid.width / Math.max(gridContainer.cols, 1)) - grid.columnSpacing
                    var cellH = (grid.height / Math.max(gridContainer.rows, 1)) - grid.rowSpacing
                    return Math.min(cellW, cellH * 16 / 9)
                }
                height: {
                    var cellW = (grid.width / Math.max(gridContainer.cols, 1)) - grid.columnSpacing
                    var cellH = (grid.height / Math.max(gridContainer.rows, 1)) - grid.rowSpacing
                    return Math.min(cellH, cellW * 9 / 16)
                }

                CameraTile {
                    anchors.centerIn: parent
                    width: cell.width
                    height: cell.height
                    cameraName: gridContainer.nameAt(index)
                    tileIndex: index
                    gridRoot: gridContainer
                    frigateRef: gridContainer.frigateRef
                    mainWindow: gridContainer.mainWindow
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
                applyFullscreenItem(fullscreenName, fullscreenSubQueue, fullscreenMainQueue)
        }
    }

    Component.onCompleted: updateGridSize()
}