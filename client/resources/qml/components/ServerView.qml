import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

import "qrc:/app/resources/qml"
import "qrc:/app/resources/qml/fullscreen"

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

    //
    // ⭐ Add Camera via PopupManager
    //
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

    //
    // ⭐ Remove Camera via PopupManager
    //
    function openRemoveCameraPopup(cameraId) {
        if (!mainWindow || !mainWindow.popupManager)
            return

        mainWindow.popupManager.openPopup(
            "qrc:/app/resources/qml/components/popups/RemoveCameraPopup.qml",
            {
                frigateRef: root.frigateRef,
                cameraId: cameraId,
                popupManager: mainWindow.popupManager
            }
        )
    }

    //
    // Camera grid loader
    //
    Loader {
        id: gridLoader
        anchors.fill: parent
        active: false
        z: 1

        onLoaded: {
            root.cameraGrid = item
            root.gridReady()

            if (root.frigateRef && root.mainWindow.cameraList) {
                for (var i = 0; i < root.mainWindow.cameraList.length; i++) {
                    var cam = root.mainWindow.cameraList[i]

                    if (root.frigateRef.isCameraOnline(cam)) {
                        if (root.cameraGrid.cameraOnline)
                            root.cameraGrid.cameraOnline(cam)
                    } else {
                        if (root.cameraGrid.cameraOffline)
                            root.cameraGrid.cameraOffline(cam)
                    }
                }
            }
        }
    }

    //
    // Initialize grid
    //
    function initializeGrid() {
        if (!mainWindow || !frigateRef) {
            console.log("ServerView: initializeGrid() called too early")
            return
        }

        gridLoader.sourceComponent = gridComponent
        gridLoader.active = true
    }

    //
    // Camera grid component
    //
    Component {
        id: gridComponent

        CameraGrid {
            id: gridContainer
            anchors.fill: parent

            mainWindow: root.mainWindow
            cameraList: root.mainWindow.cameraList
            serverViewRoot: root
            frigateRef: root.frigateRef

            //
            // ⭐ CameraGrid calls ServerView popup functions
            //
            function addCamera() {
                root.openAddCameraPopup()
            }

            function removeCamera(cameraId) {
                root.openRemoveCameraPopup(cameraId)
            }

            //
            // Timeline dock
            //
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

            //
            // Timeline live updates
            //
            Connections {
                target: root.frigateRef

                function onRecordingsLoaded(cameraId, segments) {
                    if (cameraId === root.mainWindow.selectedCameraId)
                        timeline.recordings = segments
                }

                function onEventsLoaded(cameraId, events) {
                    if (cameraId === root.mainWindow.selectedCameraId)
                        timeline.events = events
                }

                function onPlaybackPositionChanged(cameraId, positionMs) {
                    if (cameraId === root.mainWindow.selectedCameraId)
                        timeline.playbackPositionMs = positionMs
                }
            }
        }
    }

    //
    // Camera update signal
    //
    function updateCameras(list) {
        camerasLoadedToMain(list)
    }
}
