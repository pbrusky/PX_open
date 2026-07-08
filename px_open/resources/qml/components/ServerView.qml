import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// ⭐ Correct import for your QRC prefix
import "qrc:/app/resources/qml"

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

    AddCameraPopup {
        id: addCameraPopup
        frigateRef: root.frigateRef
    }

    RemoveCameraPopup {
        id: removeCameraPopup
        frigateRef: root.frigateRef
        onCameraRemoved: {
            if (root.cameraGrid && root.cameraGrid.removeCamera)
                root.cameraGrid.removeCamera(removeCameraPopup.cameraId)
        }
    }

    function openRemoveCameraPopup(cameraId) {
        if (!removeCameraPopup) {
            console.log("ServerView: removeCameraPopup is not available")
            return
        }
        removeCameraPopup.cameraId = cameraId
        removeCameraPopup.open()
    }

    Loader {
        id: gridLoader
        anchors.fill: parent
        active: false
        z: 1

        onLoaded: {
            root.cameraGrid = item
            root.gridReady()
        }
    }

    function initializeGrid() {
        if (!mainWindow || !frigateRef) {
            console.log("ServerView: initializeGrid() called too early")
            return
        }

        console.log("ServerView: initializeGrid() — mainWindow is now valid")

        gridLoader.sourceComponent = gridComponent
        gridLoader.active = true
    }

    function openAddCameraPopup() {
        if (!addCameraPopup) {
            console.log("ServerView: addCameraPopup is not available")
            return
        }
        addCameraPopup.open()
    }

    Component {
        id: gridComponent

        CameraGrid {
            id: gridContainer
            anchors.fill: parent

            mainWindow: root.mainWindow
            cameraList: root.mainWindow.cameraList
            serverViewRoot: root
            frigateRef: root.frigateRef

            FullscreenTimeline {
                id: timeline
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 80
                z: 9999

                cameraId: root.mainWindow.selectedCameraId
                cameraName: root.mainWindow.selectedCameraId
                frigateRef: root.frigateRef

                recordings: root.frigateRef
                            ? root.frigateRef.getRecordingsForCamera(root.mainWindow.selectedCameraId)
                            : []

                events: root.frigateRef
                        ? root.frigateRef.getEventsForCamera(root.mainWindow.selectedCameraId)
                        : []

                playbackPositionMs: root.frigateRef
                                    ? root.frigateRef.currentPosition(root.mainWindow.selectedCameraId)
                                    : 0
            }
        }
    }

    function updateCameras(list) {
        camerasLoadedToMain(list)
    }
}
