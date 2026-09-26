import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCore

Item {
    id: root
    objectName: "ServerView"
    anchors.fill: parent
    clip: true

    property var mainWindow
    property var frigateRef
    property var cameraGrid

    property var savedLayouts: []

    // true = hidden (same idea as sidebar/topbar/events)
    property bool timelineCollapsed: false

    property string timelineCameraId: {
        if (mainWindow && mainWindow.selectedCameraId && mainWindow.selectedCameraId.length)
            return mainWindow.selectedCameraId
        return ""
    }
    readonly property bool hideGridTimeline: mainWindow && mainWindow.cameraFullscreenActive
    readonly property real timelineExpandedHeight: 150
    readonly property real timelineBarHeight: {
        if (hideGridTimeline || timelineCollapsed)
            return 0
        return timelineExpandedHeight
    }

    signal camerasLoadedToMain(var list)
    signal gridReady()
    signal layoutsChanged()

    Settings {
        id: layoutSettings
        category: "gridLayouts"
    }

    function layoutStorageKey() {
        if (frigateRef && frigateRef.serverIp && ("" + frigateRef.serverIp).length)
            return "layouts_" + frigateRef.serverIp
        if (mainWindow && mainWindow.serverName && mainWindow.serverName.length)
            return "layouts_" + mainWindow.serverName
        return "layouts_default"
    }

    function migrateLegacyLayout() {
        var oldKey = layoutStorageKey().replace("layouts_", "layout_")
        var oldRaw = layoutSettings.value(oldKey, "")
        if (!oldRaw || oldRaw === "")
            return
        try {
            var cams = JSON.parse(oldRaw)
            if (!(cams instanceof Array))
                return
            var list = readLayoutsRaw()
            var hasDefault = false
            for (var i = 0; i < list.length; i++) {
                if (list[i].name === "Default")
                    hasDefault = true
            }
            if (!hasDefault && cams.length) {
                list.push({ name: "Default", cameras: cams })
                writeLayoutsRaw(list)
            }
            layoutSettings.setValue(oldKey, "")
        } catch (e) {}
    }

    function readLayoutsRaw() {
        var raw = layoutSettings.value(layoutStorageKey(), "")
        if (!raw || raw === "")
            return []
        try {
            var list = JSON.parse(raw)
            if (!(list instanceof Array))
                return []
            return list
        } catch (e) {
            return []
        }
    }

    function writeLayoutsRaw(list) {
        layoutSettings.setValue(layoutStorageKey(), JSON.stringify(list))
        root.savedLayouts = list.slice()
        root.layoutsChanged()
    }

    function refreshLayouts() {
        migrateLegacyLayout()
        root.savedLayouts = readLayoutsRaw()
        root.layoutsChanged()
        return root.savedLayouts
    }

    function getLayoutNames() {
        var list = readLayoutsRaw()
        var names = []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].name)
                names.push(list[i].name)
        }
        return names
    }

    function saveLayoutAs(layoutName) {
        if (!layoutName || !("" + layoutName).length)
            return false
        if (!cameraGrid || typeof cameraGrid.getLayoutNames !== "function")
            return false

        var name = ("" + layoutName).trim()
        var cams = cameraGrid.getLayoutNames()
        var list = readLayoutsRaw()
        var found = false
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === name) {
                list[i].cameras = cams
                found = true
                break
            }
        }
        if (!found)
            list.push({ name: name, cameras: cams })

        writeLayoutsRaw(list)
        return true
    }

    function saveLayout() {
        return saveLayoutAs("Default")
    }

    function loadLayoutByName(layoutName) {
        if (!layoutName || !cameraGrid || typeof cameraGrid.applyLayoutNames !== "function")
            return false
        var list = readLayoutsRaw()
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === layoutName) {
                cameraGrid.applyLayoutNames(list[i].cameras || [])
                return true
            }
        }
        return false
    }

    function loadLayout() {
        if (loadLayoutByName("Default"))
            return true
        var list = readLayoutsRaw()
        if (list.length)
            return loadLayoutByName(list[0].name)
        return false
    }

    function deleteLayout(layoutName) {
        if (!layoutName)
            return false
        var list = readLayoutsRaw()
        var next = []
        for (var i = 0; i < list.length; i++) {
            if (list[i].name !== layoutName)
                next.push(list[i])
        }
        writeLayoutsRaw(next)
        return true
    }

    function openAddCameraPopup() {
        if (!mainWindow || !mainWindow.popupManager)
            return
        mainWindow.popupManager.openPopup(
            "qrc:/app/resources/qml/components/popups/AddCameraPopup.qml",
            {
                frigateRef: root.frigateRef,
                popupManager: mainWindow.popupManager
            }
        )
    }

    function openRemoveCameraPopup(cameraId) {
        if (!mainWindow || !mainWindow.popupManager)
            return
        mainWindow.pendingRemoveCameraId = cameraId
        mainWindow.popupManager.openPopup(
            "qrc:/app/resources/qml/components/popups/RemoveCameraPopup.qml",
            {
                frigateRef: root.frigateRef,
                cameraId: cameraId,
                popupManager: mainWindow.popupManager,
                gridHost: root
            }
        )
    }

    function openEditCameraPopup(cameraId, rtspUrl, username, password) {
        if (!mainWindow || !mainWindow.popupManager)
            return
        mainWindow.popupManager.openPopup(
            "qrc:/app/resources/qml/components/popups/EditCameraPopup.qml",
            {
                frigateRef: root.frigateRef,
                cameraId: cameraId,
                rtspUrl: rtspUrl,
                username: username,
                password: password,
                popupManager: mainWindow.popupManager
            }
        )
    }

    function loadGridTimelineData() {
        if (!frigateRef || !timelineCameraId.length)
            return
        if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(timelineCameraId)
        if (typeof frigateRef.loadEvents === "function")
            frigateRef.loadEvents(timelineCameraId)
        if (typeof frigateRef.loadMotionActivity === "function")
            frigateRef.loadMotionActivity(timelineCameraId)
        if (typeof frigateRef.loadRecordingDays === "function")
            frigateRef.loadRecordingDays(timelineCameraId)
    }

    function applyGridTimelineCamera() {
        var tl = gridTimelineLoader.item
        if (!tl)
            return
        // Avoid assigning undefined into QObject* properties
        if (root.frigateRef)
            tl.frigateRef = root.frigateRef
        tl.cameraId = root.timelineCameraId
        tl.cameraName = root.timelineCameraId
        if (root.timelineCameraId.length && !root.timelineCollapsed && !root.hideGridTimeline) {
            tl.allowAutoReveal = true
            tl.collapsed = false
            Qt.callLater(loadGridTimelineData)
        } else {
            tl.allowAutoReveal = false
            tl.collapsed = true
        }
    }

    function onGridTimelineSeek(tsMs) {
        if (!cameraGrid || !timelineCameraId.length)
            return
        if (typeof cameraGrid.enterFullscreenAndSeek === "function")
            cameraGrid.enterFullscreenAndSeek(timelineCameraId, tsMs)
        else if (typeof cameraGrid.enterFullscreen === "function")
            cameraGrid.enterFullscreen(timelineCameraId)
    }

    onTimelineCameraIdChanged: {
        if (!timelineCollapsed && !hideGridTimeline)
            Qt.callLater(applyGridTimelineCamera)
    }

    onTimelineCollapsedChanged: {
        if (!timelineCollapsed && !hideGridTimeline)
            Qt.callLater(applyGridTimelineCamera)
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Loader {
            id: gridLoader
            width: parent.width
            height: parent.height - root.timelineBarHeight
            active: false
            z: 1

            onLoaded: {
                if (!item)
                    return

                item.width = Qt.binding(function() { return gridLoader.width })
                item.height = Qt.binding(function() { return gridLoader.height })
                item.mainWindow = root.mainWindow
                item.frigateRef = root.frigateRef
                item.serverViewRoot = root
                if (root.mainWindow)
                    item.cameraList = root.mainWindow.cameraList

                root.cameraGrid = item
                root.gridReady()

                if (root.frigateRef && root.mainWindow && root.mainWindow.cameraList) {
                    for (var i = 0; i < root.mainWindow.cameraList.length; i++) {
                        var cam = root.mainWindow.cameraList[i]
                        var name = (typeof cam === "string") ? cam : (cam.name || cam.id || "")
                        if (!name)
                            continue
                        if (root.frigateRef.isCameraOnline(name)) {
                            if (item.cameraOnline)
                                item.cameraOnline(name)
                        } else if (item.cameraOffline) {
                            item.cameraOffline(name)
                        }
                    }
                }

                Qt.callLater(function() {
                    root.refreshLayouts()
                    root.loadLayout()
                })
            }
        }

        // Expanded timeline only (height 0 when collapsed — like other bars)
        Item {
            id: timelineHost
            width: parent.width
            height: root.timelineBarHeight
            visible: height > 0
            clip: true

            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

            Loader {
                id: gridTimelineLoader
                anchors.fill: parent
                active: !root.hideGridTimeline
                source: "qrc:/app/resources/qml/fullscreen/FullscreenTimeline.qml"

                onLoaded: {
                    if (!item)
                        return
                    item.allowAutoReveal = false
                    item.collapsed = false
                    if (root.frigateRef)
                        item.frigateRef = root.frigateRef
                    if (item.seekRequested)
                        item.seekRequested.connect(root.onGridTimelineSeek)
                    root.applyGridTimelineCamera()
                }
            }
        }
    }

    // Camera name above the arrow when timeline is collapsed
    Text {
        id: collapsedCamName
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        z: 10001
        visible: root.timelineCollapsed
                 && root.timelineCameraId.length > 0
                 && !root.hideGridTimeline
                 && root.mainWindow
                 && !root.mainWindow.cameraFullscreenActive
        text: root.timelineCameraId
        color: "#C8C8D0"
        font.pixelSize: 12
        font.bold: true
    }

    // Same control as topbar / sidebar / events — NX arrow IconButton
    IconButton {
        id: timelineArrow
        width: 32
        height: 32
        z: 10001

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.timelineCollapsed ? 4 : (root.timelineBarHeight + 4)

        icon: root.timelineCollapsed
              ? "qrc:/app/assets/icons/nx/arrow-up.svg"
              : "qrc:/app/assets/icons/nx/arrow-down.svg"

        visible: !root.hideGridTimeline
                 && root.mainWindow
                 && !root.mainWindow.cameraFullscreenActive

        onClicked: root.timelineCollapsed = !root.timelineCollapsed

        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
    }

    function initializeGrid() {
        if (!mainWindow || !frigateRef) {
            console.log("ServerView: initializeGrid() called too early")
            return
        }
        gridLoader.source = ""
        gridLoader.source = "qrc:/app/resources/qml/components/CameraGrid.qml"
        gridLoader.active = true
    }

    function updateCameras(list) {
        camerasLoadedToMain(list)
        if (cameraGrid) {
            cameraGrid.cameraList = list
            if (typeof cameraGrid.pruneMissingCameras === "function")
                cameraGrid.pruneMissingCameras(list)
            Qt.callLater(function() {
                root.refreshLayouts()
                root.loadLayout()
            })
        }
    }

    function removeFromGrid(cameraId) {
        if (!cameraId || !cameraGrid)
            return
        if (typeof cameraGrid.removeCameraByName === "function")
            cameraGrid.removeCameraByName(cameraId)
    }

    function clearAllFromGrid() {
        if (!cameraGrid)
            return
        if (typeof cameraGrid.clearAllTiles === "function") {
            console.log("ServerView: clearAllFromGrid")
            cameraGrid.clearAllTiles()
        }
    }
}