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
        var id = timelineCameraId
        if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)
        if (typeof frigateRef.loadEvents === "function")
            frigateRef.loadEvents(id)
        if (typeof frigateRef.loadMotionActivity === "function")
            frigateRef.loadMotionActivity(id)
        if (typeof frigateRef.loadRecordingDays === "function")
            frigateRef.loadRecordingDays(id)
    }

    function clearGridTimelineTrack(tl) {
        if (!tl)
            return
        tl.recordings = []
        tl.events = []
        tl.motionPoints = []
        if (tl.recordingDays !== undefined)
            tl.recordingDays = []
        if (tl._fixedDayMode !== undefined)
            tl._fixedDayMode = false
        if (tl.hoverTsMs !== undefined)
            tl.hoverTsMs = -1
        if (tl.playbackPositionMs !== undefined)
            tl.playbackPositionMs = 0
    }

    function applyCachedTimeline(tl, id) {
        if (!tl || !root.frigateRef || !id.length)
            return false
        var had = false
        if (typeof root.frigateRef.getRecordingsForCamera === "function") {
            var r = root.frigateRef.getRecordingsForCamera(id) || []
            if (r.length) {
                tl.recordings = r
                had = true
            }
        }
        if (typeof root.frigateRef.getEventsForCamera === "function") {
            var e = root.frigateRef.getEventsForCamera(id) || []
            if (e.length) {
                tl.events = e
                had = true
            }
        }
        if (typeof root.frigateRef.getMotionActivityForCamera === "function") {
            var m = root.frigateRef.getMotionActivityForCamera(id) || []
            if (m.length) {
                tl.motionPoints = m
                had = true
            }
        }
        if (typeof root.frigateRef.getRecordingDaysForCamera === "function") {
            var d = root.frigateRef.getRecordingDaysForCamera(id) || []
            if (d.length)
                tl.recordingDays = d
        }
        return had
    }

    // Warm cache for cameras on the grid (NX-style)
    function prefetchGridTimelineCameras() {
        if (!frigateRef || !mainWindow || !mainWindow.cameraList)
            return
        var list = mainWindow.cameraList
        var n = Math.min(list.length, 12)
        for (var i = 0; i < n; i++) {
            var cam = list[i]
            var id = (typeof cam === "string") ? cam : (cam.id || cam.name || "")
            if (!id.length)
                continue
            var hasRec = false
            if (typeof frigateRef.getRecordingsForCamera === "function") {
                var r = frigateRef.getRecordingsForCamera(id)
                hasRec = r && r.length > 0
            }
            if (hasRec)
                continue
            if (typeof frigateRef.loadRecordings === "function")
                frigateRef.loadRecordings(id)
            if (typeof frigateRef.loadMotionActivity === "function")
                frigateRef.loadMotionActivity(id)
        }
    }

    function applyGridTimelineCamera() {
        var tl = gridTimelineLoader.item
        if (!tl)
            return

        if (root.frigateRef)
            tl.frigateRef = root.frigateRef

        var id = root.timelineCameraId
        tl.cameraId = id
        tl.cameraName = id

        if (id.length && !root.timelineCollapsed && !root.hideGridTimeline) {
            tl.allowAutoReveal = true
            tl.collapsed = false

            // NX: paint cache without blanking; only clear if no cache yet
            if (!applyCachedTimeline(tl, id))
                clearGridTimelineTrack(tl)

            Qt.callLater(function() {
                if (root.timelineCameraId === id)
                    root.loadGridTimelineData()
            })
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
        if (!hideGridTimeline)
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
                    root.prefetchGridTimelineCameras()
                })
            }
        }

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
                root.prefetchGridTimelineCameras()
            })
        } else {
            Qt.callLater(function() {
                root.prefetchGridTimelineCameras()
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