import QtQuick 2.15
import QtQuick.Window 2.15
import PxOpen 1.0

Item {
    id: root

    property var mainWindow
    property var frigateRef

    property string fullscreenCameraKey: ""
    property var fullscreenLiveQueue: null

    // actual fullscreen window created in C++
    property var fullscreenWindow: null

    //
    // Open fullscreen using native C++ window
    //
    function open(cameraKey, liveQueue) {
        if (!cameraKey)
            return

        fullscreenCameraKey = cameraKey
        fullscreenLiveQueue = liveQueue

        fullscreenWindow = FullscreenHelper.openFullscreen(
            Qt.application.engine,
            "qrc:/app/resources/qml/fullscreen/FullscreenCamera.qml"
        )

        fullscreenWindow.cameraId = cameraKey
        fullscreenWindow.cameraName = cameraKey
        fullscreenWindow.frigateRef = frigateRef
        fullscreenWindow.liveQueue = liveQueue
        fullscreenWindow.isOnline = frigateRef.isCameraOnline(cameraKey)

        // ESC and double‑click handled inside FullscreenCamera.qml
        fullscreenWindow.open()
    }

    //
    // Close fullscreen
    //
    function close() {
        if (fullscreenWindow) {
            fullscreenWindow.close()
            fullscreenWindow.destroy()
            fullscreenWindow = null
        }
    }
}
