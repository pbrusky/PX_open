import QtQuick 2.15

Item {
    id: root

    property var mainWindow
    property var frigateRef
    property var topbar
    property var sidebarWrapper
    property var contentLoader
    property var restartPopup
    property var frigatePollTimer
    property var popupManager

    property bool restartInProgress: false
    property real restartStartedAt: 0

    function dismissCurrentPopup() {
        if (popupManager && typeof popupManager.closePopup === "function") {
            popupManager.closePopup()
            return
        }
        if (mainWindow && mainWindow.popupManager)
            mainWindow.popupManager.closePopup()
    }

    function showRestartOverlay() {
        dismissCurrentPopup()

        restartInProgress = true
        restartStartedAt = Date.now()

        if (restartPopup) {
            restartPopup.z = 2000000
            if (typeof restartPopup.open === "function")
                restartPopup.open()
            else
                restartPopup.visible = true
        }

        restartMaxTimer.restart()
        pollDelayTimer.restart()
    }

    function startRestartFlow() {
        dismissCurrentPopup()
        Qt.callLater(showRestartOverlay)
    }

    function stopRestartFlow() {
        restartInProgress = false

        if (pollDelayTimer.running)
            pollDelayTimer.stop()
        if (restartMaxTimer.running)
            restartMaxTimer.stop()

        if (frigatePollTimer && frigatePollTimer.running)
            frigatePollTimer.stop()

        if (restartPopup) {
            if (typeof restartPopup.close === "function")
                restartPopup.close()
            else
                restartPopup.visible = false
        }
    }

    Timer {
        id: pollDelayTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!restartInProgress)
                return
            if (frigatePollTimer) {
                frigatePollTimer.interval = 2000
                frigatePollTimer.start()
            }
            if (frigateRef)
                frigateRef.loadCameras()
        }
    }

    Timer {
        id: restartMaxTimer
        interval: 90000
        repeat: false
        onTriggered: {
            if (restartInProgress) {
                console.log("MainWindowConnections: restart max timeout — closing overlay")
                if (frigateRef)
                    frigateRef.loadCameras()
                stopRestartFlow()
            }
        }
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onCamerasLoaded(list) {
            if (!list)
                list = []

            mainWindow.cameraList = list
            if (sidebarWrapper)
                sidebarWrapper.cameraList = list

            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.updateCameras) {
                contentLoader.item.updateCameras(list)
            }

            mainWindow.camerasLoaded(list)

            if (restartInProgress) {
                var elapsed = Date.now() - restartStartedAt
                // Wait until Frigate is actually back with cameras.
                // Empty list means Frigate is still down — keep polling.
                if (list.length > 0 && elapsed >= 4000) {
                    console.log("MainWindowConnections: Frigate up — closing restart overlay, cameras=", list.length)
                    stopRestartFlow()
                } else if (elapsed >= 90000) {
                    console.log("MainWindowConnections: restart timeout — closing overlay, cameras=", list.length)
                    stopRestartFlow()
                } else {
                    console.log("MainWindowConnections: still waiting for Frigate… elapsed=", elapsed, "cameras=", list.length)
                }
                return
            }

            if (frigatePollTimer && frigatePollTimer.running)
                frigatePollTimer.stop()

            if (restartPopup) {
                if (typeof restartPopup.close === "function")
                    restartPopup.close()
                else
                    restartPopup.visible = false
            }
        }

        function onCameraOffline(name) {
            for (var i = 0; i < mainWindow.cameraList.length; ++i)
                if (mainWindow.cameraList[i].name === name)
                    mainWindow.cameraList[i].isOnline = false

            if (sidebarWrapper)
                sidebarWrapper.cameraList = mainWindow.cameraList
            mainWindow.cameraOffline(name)
        }

        function onCameraOnline(name) {
            for (var i = 0; i < mainWindow.cameraList.length; ++i)
                if (mainWindow.cameraList[i].name === name)
                    mainWindow.cameraList[i].isOnline = true

            if (sidebarWrapper)
                sidebarWrapper.cameraList = mainWindow.cameraList
            mainWindow.cameraOnline(name)
        }

        function onCameraAddResult(ok, message) {
            console.log("MainWindowConnections cameraAddResult", ok, message)
            if (ok)
                startRestartFlow()
            else
                dismissCurrentPopup()
        }

        function onCameraEditResult(ok, message) {
            console.log("MainWindowConnections cameraEditResult", ok, message)
            if (ok)
                startRestartFlow()
            else
                dismissCurrentPopup()
        }

        function onCameraRemoveResult(ok, message) {
            console.log("MainWindowConnections cameraRemoveResult", ok, message)
            if (mainWindow)
                mainWindow.pendingRemoveCameraId = ""
            if (ok)
                startRestartFlow()
            else
                dismissCurrentPopup()
        }

        function onFrigateConfigSaved(ok, message) {
            console.log("MainWindowConnections frigateConfigSaved", ok, message)
            if (ok)
                startRestartFlow()
            else
                dismissCurrentPopup()
        }

        function onGo2rtcConfigSaved(ok, message) {
            console.log("MainWindowConnections go2rtcConfigSaved", ok, message)
            if (ok)
                startRestartFlow()
            else
                dismissCurrentPopup()
        }
    }

    Connections {
        target: topbar
        ignoreUnknownSignals: true

        function onDisconnectRequested() {
            stopRestartFlow()

            contentLoader.startupDone = false
            contentLoader.source = "qrc:/app/resources/qml/StartupPage.qml"

            mainWindow.serverName = ""
            frigateRef.server = ""
            frigateRef.serverIp = ""

            mainWindow.showNormal()

            mainWindow.width = 1400
            mainWindow.height = 900
            mainWindow.x = (mainWindow.screen.width - mainWindow.width) / 2
            mainWindow.y = (mainWindow.screen.height - mainWindow.height) / 2

            topbar.isMaximized = false
        }

        function onAddCameraRequested() {
            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.openAddCameraPopup) {
                contentLoader.item.openAddCameraPopup()
            }
        }

        function onExitRequested() {
            Qt.quit()
        }

        function onMinimizeRequested() {
            mainWindow.showMinimized()
        }

        function onMaximizeRequested() {
            mainWindow.showMaximized()
            topbar.isMaximized = true
        }

        function onRestoreRequested() {
            mainWindow.showNormal()

            mainWindow.width = 1400
            mainWindow.height = 900
            mainWindow.x = (mainWindow.screen.width - mainWindow.width) / 2
            mainWindow.y = (mainWindow.screen.height - mainWindow.height) / 2

            topbar.isMaximized = false
        }
    }
}