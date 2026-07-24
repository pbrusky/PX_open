import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

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

    //
    // Add Camera Popup (delayed creation)
    //
    Loader {
        id: addCameraPopupLoader
        active: root.frigateRef !== undefined
        source: "qrc:/app/resources/qml/components/AddCameraPopup.qml"

        onLoaded: {
            item.frigateRef = root.frigateRef
        }
    }

    function openAddCameraPopup() {
        if (addCameraPopupLoader.item)
            addCameraPopupLoader.item.open()
    }

    //
    // Remove Camera Popup (delayed creation)
    //
    Loader {
        id: removeCameraPopupLoader
        active: root.frigateRef !== undefined
        source: "qrc:/app/resources/qml/components/RemoveCameraPopup.qml"

        onLoaded: {
            item.frigateRef = root.frigateRef

            item.cameraRemoved.connect(function(cameraId) {
                if (root.cameraGrid && root.cameraGrid.removeCamera)
                    root.cameraGrid.removeCamera(cameraId)
            })
        }
    }

    function openRemoveCameraPopup(cameraId) {
        if (removeCameraPopupLoader.item) {
            removeCameraPopupLoader.item.cameraId = cameraId
            removeCameraPopupLoader.item.open()
        }
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
