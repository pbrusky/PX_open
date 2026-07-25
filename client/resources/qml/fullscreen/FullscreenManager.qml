import QtQuick 2.15

Item {
    id: root

    property var mainWindow
    property var frigateRef
    property var fullscreenLoader

    // camera name from tile
    property string fullscreenCameraKey: ""

    // queue passed from CameraTile
    property var fullscreenLiveQueue: null

    //
    // Open fullscreen
    //
    function open(cameraKey, liveQueue) {
        if (!cameraKey)
            return

        fullscreenCameraKey = cameraKey
        fullscreenLiveQueue = liveQueue

        fullscreenLoader.source = "qrc:/app/resources/qml/FullscreenCamera.qml"
        fullscreenLoader.visible = true
    }

    //
    // Close fullscreen
    //
    function close() {
        if (fullscreenLoader.item && fullscreenLoader.item.close)
            fullscreenLoader.item.close()

        fullscreenLoader.visible = false
    }

    //
    // Initialize fullscreen camera when loader finishes
    //
    Connections {
        target: fullscreenLoader
        ignoreUnknownSignals: true

        function onLoaded(item) {
            if (!item)
                return

            // pass camera name
            item.cameraId = root.fullscreenCameraKey
            item.cameraName = root.fullscreenCameraKey

            // pass frigateRef
            item.frigateRef = root.frigateRef

            // pass liveQueue
            item.liveQueue = root.fullscreenLiveQueue

            // online state
            item.isOnline = root.frigateRef.isCameraOnline(root.fullscreenCameraKey)

            // call fullscreen open()
            if (item.open)
                item.open()
        }
    }
}
