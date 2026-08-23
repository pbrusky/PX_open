import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    objectName: "ServerView"
    anchors.fill: parent
    clip: true

    property var mainWindow
    property var frigateRef
    property var cameraGrid

    signal camerasLoadedToMain(var list)
    signal gridReady()

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
        }
    }

    function removeFromGrid(cameraId) {
        if (!cameraId || !cameraGrid)
            return
        if (typeof cameraGrid.removeCameraByName === "function")
            cameraGrid.removeCameraByName(cameraId)
    }

    // Clear entire grid before system remove (restart kills remaining streams)
    function clearAllFromGrid() {
        if (!cameraGrid)
            return
        if (typeof cameraGrid.clearAllTiles === "function") {
            console.log("ServerView: clearAllFromGrid")
            cameraGrid.clearAllTiles()
        }
    }
}