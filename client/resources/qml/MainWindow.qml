import PxOpen 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import "qrc:/app/resources/qml/components"

ApplicationWindow {
    id: mainWindow
    width: 1400
    height: 900
    visible: true
    color: "black"

    flags: Qt.Window | Qt.FramelessWindowHint

    property var frigateRef: frigate
    property var cameraList: []
    property string selectedCameraId: ""
    property string serverName: ""
    property string _fullscreenCameraKey: ""

    signal cameraOnline(string name)
    signal cameraOffline(string name)
    signal camerasLoaded(var list)

    RestartPopup {
        id: restartPopup
        visible: false
        z: 999999
    }

    Timer {
        id: frigatePollTimer
        interval: 1500
        repeat: true

        onTriggered: {
            if (frigateRef)
                frigateRef.loadCameras()
        }
    }

    function loadCameras() {
        if (frigateRef)
            frigateRef.loadCameras()
    }

    Loader {
        id: fullscreenLoader
        anchors.fill: parent
        z: 99999
        visible: false

        onLoaded: {
            if (!item) return

            item.cameraId = _fullscreenCameraKey
            item.cameraName = _fullscreenCameraKey
            item.frigateRef = frigateRef
            item.isOnline = frigateRef.isCameraOnline(_fullscreenCameraKey)

            if (item.open)
                item.open()
        }
    }

    function openFullscreen(cameraKey) {
        if (!cameraKey) return
        _fullscreenCameraKey = cameraKey
        fullscreenLoader.source = "qrc:/app/resources/qml/FullscreenCamera.qml"
        fullscreenLoader.visible = true
    }

    function closeFullscreen() {
        if (fullscreenLoader.item && fullscreenLoader.item.close)
            fullscreenLoader.item.close()
        fullscreenLoader.visible = false
    }

    function handleCameraDrop(x, y, cameraName) {
        let sv = contentLoader.item
        if (!sv || sv.objectName !== "ServerView")
            return

        let grid = sv.cameraGrid
        if (!grid || !grid.dropAt) {
            sv.gridReady.connect(function() {
                let g = sv.cameraGrid
                if (!g || !g.dropAt) return
                let p2 = g.mapFromGlobal(x, y)
                g.dropAt(p2.x, p2.y, cameraName)
            })
            return
        }

        let p = grid.mapFromGlobal(x, y)
        grid.dropAt(p.x, p.y, cameraName)
    }

    TopBar {
        id: topbar
        width: parent.width
        height: 48
        z: 9999

        // ⭐ REMOVED the click‑stealing MouseArea here

        property bool collapsed: false

        y: collapsed ? -height : 0
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        isStartupPage: contentLoader.item && contentLoader.item.objectName === "StartupPage"
        isCameraPage: contentLoader.item && contentLoader.item.objectName === "ServerView"
        serverName: mainWindow.serverName
    }

    IconButton {
        id: topbarArrow
        width: 32
        height: 32
        x: (mainWindow.width / 2) - (width / 2)
        y: topbar.collapsed ? 4 : topbar.height + 4
        z: 10000

        icon: topbar.collapsed
              ? "qrc:/app/assets/icons/nx/arrow-down.svg"
              : "qrc:/app/assets/icons/nx/arrow-up.svg"

        visible: !topbar.isStartupPage
        onClicked: topbar.collapsed = !topbar.collapsed

        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
    }

    Sidebar {
        id: sidebarWrapper
        objectName: "Sidebar"

        frigateRef: mainWindow.frigateRef

        width: 260
        height: mainWindow.height - topbar.height
        y: topbar.height
        z: 9998

        property bool collapsed: false

        x: collapsed ? -width : 0
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        visible: contentLoader.item && contentLoader.item.objectName === "ServerView"

        cameraList: mainWindow.cameraList
        selectedCameraId: mainWindow.selectedCameraId
        serverName: mainWindow.serverName

        onCameraSelected: function(cameraId) {
            mainWindow.selectedCameraId = cameraId
        }

        onRequestRemoveCamera: function(id) {
            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.openRemoveCameraPopup) {
                contentLoader.item.openRemoveCameraPopup(id)
            }
        }

        onCameraDropped: function(x, y, cameraName) {
            mainWindow.handleCameraDrop(x, y, cameraName)
        }

        onNavigate: function(page) {
            if (page === "qrc:/app/resources/qml/StartupPage.qml") {
                contentLoader.startupDone = false
                contentLoader.source = page
                return
            }

            if (page === "disconnect") {
                topbar.disconnectRequested()
                return
            }

            if (page === "addCamera") {
                if (contentLoader.item &&
                    contentLoader.item.objectName === "ServerView" &&
                    contentLoader.item.openAddCameraPopup) {
                    contentLoader.item.openAddCameraPopup()
                }
                return
            }

            if (page === "reloadCameras") {
                mainWindow.loadCameras()
                return
            }

            contentLoader.source = page
        }
    }

    IconButton {
        id: sidebarReturnArrow
        width: 32
        height: 32

        x: sidebarWrapper.collapsed
            ? 4
            : sidebarWrapper.x + sidebarWrapper.width - 36

        y: topbar.height + (mainWindow.height - topbar.height) / 2 - height / 2

        z: 10001

        icon: sidebarWrapper.collapsed
              ? "qrc:/app/assets/icons/nx/arrow-right.svg"
              : "qrc:/app/assets/icons/nx/arrow-left.svg"

        visible: !topbar.isStartupPage
        onClicked: sidebarWrapper.collapsed = !sidebarWrapper.collapsed

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        z: 2

        anchors.topMargin: topbar.collapsed ? 0 : topbar.height
        anchors.leftMargin: (sidebarWrapper.collapsed || topbar.isStartupPage) ? 0 : sidebarWrapper.width

        property bool startupDone: false

        source: startupDone
                ? "qrc:/app/resources/qml/components/ServerView.qml"
                : "qrc:/app/resources/qml/StartupPage.qml"

        onLoaded: {
            if (!item) return

            if (item.objectName === "StartupPage") {
                item.discovery = discovery
                item.frigateRef = frigateRef

                item.serverSelected.connect(function(name, ip, apiPort, modulePort) {
                    mainWindow.serverName = name

                    frigateRef.serverIp = ip
                    frigateRef.server = "http://" + ip + ":" + apiPort
                    frigateRef.setModuleServer("http://" + ip + ":" + modulePort)

                    contentLoader.startupDone = true
                    contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"

                    mainWindow.showMaximized()
                    topbar.isMaximized = true
                })
            }

            if (item.objectName !== "StartupPage" && discovery)
                discovery.stopDiscovery()

            if (item.objectName === "ServerView") {
                item.frigateRef = frigateRef
                item.mainWindow = mainWindow

                item.initializeGrid()
                frigateRef.loadCameras()

                item.camerasLoadedToMain.connect(function(list) {
                    mainWindow.cameraList = list
                    sidebarWrapper.cameraList = list
                })
            }
        }
    }

    AddCameraPopup {
        id: addCameraPopup
        frigateRef: mainWindow.frigateRef
    }

    RemoveCameraPopup {
        id: removePopup
        frigateRef: mainWindow.frigateRef
    }

    Connections {
        target: frigateRef

        function onCamerasLoaded(list) {

            if (!list || list.length === 0) {
                console.log("Frigate still restarting… camera list empty")
                return
            }

            mainWindow.cameraList = list
            sidebarWrapper.cameraList = list

            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.updateCameras)
                contentLoader.item.updateCameras(list)

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

    Connections {
        target: topbar

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
