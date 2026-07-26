import QtQuick 2.15
import "qrc:/app/resources/qml/components/popups"

Item {
    id: root

    // These must NOT have default bindings
    property var mainWindow
    property var frigateRef
    property var topbar
    property var sidebarWrapper
    property var contentLoader
    property var restartPopup
    property var frigatePollTimer

    //
    // Frigate signals
    //
    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onCamerasLoaded(list) {
            if (!list || list.length === 0)
                return

            mainWindow.cameraList = list
            sidebarWrapper.cameraList = list

            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.updateCameras)
            {
                contentLoader.item.updateCameras(list)
            }

            mainWindow.camerasLoaded(list)

            if (frigatePollTimer.running)
                frigatePollTimer.stop()

            restartPopup.visible = false
        }

        function onCameraOffline(name) {
            for (var i = 0; i < mainWindow.cameraList.length; ++i)
                if (mainWindow.cameraList[i].name === name)
                    mainWindow.cameraList[i].isOnline = false

            sidebarWrapper.cameraList = mainWindow.cameraList
            mainWindow.cameraOffline(name)
        }

        function onCameraOnline(name) {
            for (var i = 0; i < mainWindow.cameraList.length; ++i)
                if (mainWindow.cameraList[i].name === name)
                    mainWindow.cameraList[i].isOnline = true

            sidebarWrapper.cameraList = mainWindow.cameraList
            mainWindow.cameraOnline(name)
        }

        function onCameraAddResult(ok, message) {
            restartPopup.visible = true
            frigatePollTimer.start()
            frigateRef.loadCameras()
        }

        function onCameraEditResult(ok, message) {
            restartPopup.visible = true
            frigatePollTimer.start()
            frigateRef.loadCameras()
        }

        function onCameraRemoveResult(ok, message) {
            restartPopup.visible = true
            frigatePollTimer.start()
            frigateRef.loadCameras()
        }
    }

    //
    // Topbar signals
    //
    Connections {
        target: topbar
        ignoreUnknownSignals: true

        function onDisconnectRequested() {
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
                contentLoader.item.openAddCameraPopup)
            {
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
