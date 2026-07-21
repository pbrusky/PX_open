import QtQuick 2.15

Item {
    id: restartController
    property var frigateRef

    signal restartStarted()
    signal restartFinished()

    Timer {
        id: pollTimer
        interval: 1500
        repeat: true
        onTriggered: {
            if (frigateRef)
                frigateRef.loadCameras()
        }
    }

    function startRestartFlow() {
        restartPopup.visible = true
        pollTimer.start()
        if (frigateRef)
            frigateRef.loadCameras()
        restartStarted()
    }

    function handleCamerasLoaded(list) {
        if (list.length > 0) {
            pollTimer.stop()
            restartPopup.visible = false
            restartFinished()
        }
    }
}
