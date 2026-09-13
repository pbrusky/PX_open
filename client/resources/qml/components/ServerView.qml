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

    // [{ name: "…", cameras: ["id1", "id2"] }, ...]
    property var savedLayouts: []

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

    // Migrate old single-layout key once
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

    // Save current grid under a name (overwrite if same name)
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

    // Back-compat: old "Save Layout" without a name
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

    // Back-compat: load Default or first
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

    Loader {
        id: gridLoader
        anchors.fill: parent
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
                    } else {
                        if (item.cameraOffline)
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