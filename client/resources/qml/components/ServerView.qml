import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCore

Item {
    id: root
    objectName: "ServerView"
    anchors.fill: parent
    clip: false

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

    // Staggered recordings-only prefetch (motion loads for selected camera only)
    property var _prefetchQueue: []
    property int _prefetchIndex: 0

    signal camerasLoadedToMain(var list)
    signal gridReady()
    signal layoutsChanged()

    Settings {
        id: layoutSettings
        category: "gridLayouts"
    }

    Timer {
        id: prefetchTimer
        interval: 400
        repeat: true
        onTriggered: root.prefetchStep()
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

    // Recordings + motion ticks + days. Events stay on the Events panel.
    function loadGridTimelineData() {
        if (!frigateRef || !timelineCameraId.length)
            return
        var id = timelineCameraId
        if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)
        if (typeof frigateRef.loadMotionActivity === "function")
            frigateRef.loadMotionActivity(id)
        if (typeof frigateRef.loadRecordingDays === "function")
            frigateRef.loadRecordingDays(id)
    }

    function fetchMotionList(id) {
        if (!root.frigateRef || !id.length)
            return []
        if (typeof root.frigateRef.getMotionActivityForCamera === "function") {
            var m = root.frigateRef.getMotionActivityForCamera(id)
            if (m && m.length)
                return m
        }
        if (typeof root.frigateRef.getMotionActivity === "function") {
            var m2 = root.frigateRef.getMotionActivity(id)
            if (m2 && m2.length)
                return m2
        }
        return []
    }

    function applyMotionToGrid(id, points) {
        var tl = gridTimelineLoader.item
        if (!tl || !id.length)
            return
        if (tl.cameraId !== id && tl.cameraName !== id)
            return
        if (typeof tl.applyMotionPoints === "function")
            tl.applyMotionPoints(points || [])
        else
            tl.motionPoints = points || []
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
                if (r.length > 0) {
                    tl.startTs = Number(r[0].start)
                    tl.endTs = Number(r[r.length - 1].end)
                }
                had = true
            }
        }

        if (typeof root.frigateRef.getRecordingDaysForCamera === "function") {
            var d = root.frigateRef.getRecordingDaysForCamera(id) || []
            if (d.length)
                tl.recordingDays = d
        }

        // Motion ticks from RAM/disk cache
        var m = root.fetchMotionList(id)
        if (m.length) {
            if (typeof tl.applyMotionPoints === "function")
                tl.applyMotionPoints(m)
            else
                tl.motionPoints = m
            had = true
        }

        return had
    }

    function prefetchStep() {
        if (!frigateRef || _prefetchIndex >= _prefetchQueue.length) {
            prefetchTimer.stop()
            return
        }
        var id = _prefetchQueue[_prefetchIndex++]
        if (!id || !id.length)
            return
        var hasRec = false
        if (typeof frigateRef.getRecordingsForCamera === "function") {
            var r = frigateRef.getRecordingsForCamera(id)
            hasRec = r && r.length > 0
        }
        if (!hasRec && typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)
    }

    function prefetchGridTimelineCameras() {
        if (!frigateRef || !mainWindow || !mainWindow.cameraList)
            return

        _prefetchQueue = []
        _prefetchIndex = 0

        if (timelineCameraId && timelineCameraId.length)
            _prefetchQueue.push(timelineCameraId)

        var list = mainWindow.cameraList
        var n = Math.min(list.length, 12)
        for (var i = 0; i < n; i++) {
            var cam = list[i]
            var id = (typeof cam === "string") ? cam : (cam.id || cam.name || "")
            if (!id.length || id === timelineCameraId)
                continue
            _prefetchQueue.push(id)
        }

        prefetchTimer.start()
        prefetchStep()
    }

    function applyGridTimelineCamera() {
        var tl = gridTimelineLoader.item
        if (!tl)
            return

        // Set API first so Connections on the timeline can receive signals
        if (root.frigateRef)
            tl.frigateRef = root.frigateRef

        var id = root.timelineCameraId
        tl.cameraId = id
        tl.cameraName = id

        if (id.length && !root.timelineCollapsed && !root.hideGridTimeline) {
            tl.allowAutoReveal = true
            tl.collapsed = false

            clearGridTimelineTrack(tl)
            applyCachedTimeline(tl, id)

            Qt.callLater(function() {
                if (root.timelineCameraId !== id)
                    return
                root.loadGridTimelineData()
                // After load* may fill cache synchronously from disk
                Qt.callLater(function() {
                    if (root.timelineCameraId === id && gridTimelineLoader.item)
                        root.applyCachedTimeline(gridTimelineLoader.item, id)
                })
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

    function attachTimelineToWindow() {
        if (!mainWindow || !mainWindow.contentItem)
            return
        if (timelineLayer.parent === mainWindow.contentItem)
            return
        timelineLayer.parent = mainWindow.contentItem
        timelineLayer.z = 10050
        timelineLayer.anchors.left = mainWindow.contentItem.left
        timelineLayer.anchors.right = mainWindow.contentItem.right
        timelineLayer.anchors.bottom = mainWindow.contentItem.bottom
        timelineLayer.anchors.top = undefined
    }

    function detachTimelineFromWindow() {
        if (timelineLayer.parent === root)
            return
        timelineLayer.anchors.left = undefined
        timelineLayer.anchors.right = undefined
        timelineLayer.anchors.bottom = undefined
        timelineLayer.parent = root
        timelineLayer.z = 10050
        timelineLayer.anchors.left = root.left
        timelineLayer.anchors.right = root.right
        timelineLayer.anchors.bottom = root.bottom
    }

    onMainWindowChanged: Qt.callLater(attachTimelineToWindow)
    Component.onCompleted: Qt.callLater(attachTimelineToWindow)

    onTimelineCameraIdChanged: {
        if (!hideGridTimeline)
            Qt.callLater(applyGridTimelineCamera)
    }

    onTimelineCollapsedChanged: {
        if (!timelineCollapsed && !hideGridTimeline)
            Qt.callLater(applyGridTimelineCamera)
    }

    onHideGridTimelineChanged: {
        // Leaving fullscreen recreates the timeline Loader — re-apply motion
        if (!hideGridTimeline)
            Qt.callLater(applyGridTimelineCamera)
    }

    // Push motion/recordings onto grid timeline when API signals fire
    // (Loader is often destroyed during fullscreen; this path still works)
    Connections {
        target: root.frigateRef
        ignoreUnknownSignals: true

        function onMotionActivityLoaded(camId, points) {
            root.applyMotionToGrid(camId, points)
        }

        function onRecordingsLoaded(camId, segments) {
            var tl = gridTimelineLoader.item
            if (!tl || (camId !== tl.cameraId && camId !== tl.cameraName))
                return
            tl.recordings = segments || []
            if (tl.recordings.length > 0) {
                tl.startTs = Number(tl.recordings[0].start)
                tl.endTs = Number(tl.recordings[tl.recordings.length - 1].end)
            }
        }

        function onRecordingDaysLoaded(camId, days) {
            var tl = gridTimelineLoader.item
            if (!tl || (camId !== tl.cameraId && camId !== tl.cameraName))
                return
            tl.recordingDays = days || []
        }
    }

    Loader {
        id: gridLoader
        anchors.fill: parent
        anchors.bottomMargin: root.timelineBarHeight
        active: false
        z: 1

        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }

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
        id: timelineLayer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.timelineBarHeight > 0 ? root.timelineBarHeight : 36
        z: 10050
        visible: !root.hideGridTimeline
                 && root.mainWindow
                 && !root.mainWindow.cameraFullscreenActive

        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }

        Item {
            id: timelineHost
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.timelineBarHeight
            visible: height > 0
            clip: true

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

        Text {
            id: collapsedCamName
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40
            z: 2
            visible: root.timelineCollapsed
                     && root.timelineCameraId.length > 0
                     && !root.hideGridTimeline
            text: root.timelineCameraId
            color: "#C8C8D0"
            font.pixelSize: 12
            font.bold: true
        }

        IconButton {
            id: timelineArrow
            width: 32
            height: 32
            z: 3

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4

            icon: root.timelineCollapsed
                  ? "qrc:/app/assets/icons/nx/arrow-up.svg"
                  : "qrc:/app/assets/icons/nx/arrow-down.svg"

            visible: !root.hideGridTimeline
            onClicked: root.timelineCollapsed = !root.timelineCollapsed
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
        Qt.callLater(attachTimelineToWindow)
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