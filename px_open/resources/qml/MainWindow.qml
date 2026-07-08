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

    // ⭐ Remove Windows title bar
    flags: Qt.FramelessWindowHint

    //
    // State
    //
    property var cameraList: []
    property string selectedCameraId: ""
    property string serverName: ""
    property string _fullscreenCameraKey: ""

    //
    // Signals
    //
    signal cameraOnline(string name)
    signal cameraOffline(string name)
    signal camerasLoaded(var list)

    //
    // Fullscreen Loader
    //
    Loader {
        id: fullscreenLoader
        anchors.fill: parent
        z: 99999
        visible: false

        onLoaded: {
            if (!item) return

            item.cameraId = _fullscreenCameraKey
            item.cameraName = _fullscreenCameraKey
            item.frigateRef = frigate
            item.isOnline = false

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

    //
    // Drag & Drop from Sidebar → CameraGrid
    //
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

    //
    // Top Bar
    //
    TopBar {
        id: topbar
        width: parent.width
        height: 48
        z: 9999

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

    //
    // Sidebar
    //
    Sidebar {
        id: sidebarWrapper
        objectName: "Sidebar"

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
                if (contentLoader.item &&
                    contentLoader.item.objectName === "ServerView") {
                    if (contentLoader.item.reloadCameras)
                        contentLoader.item.reloadCameras()
                    else if (frigate)
                        frigate.loadCameras()
                } else if (frigate) {
                    frigate.loadCameras()
                }
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

    //
    // Main Content Loader (StartupPage → ServerView)
    //
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
                item.frigate = frigate

                item.serverSelected.connect(function(name, ip, port) {
                    mainWindow.serverName = name
                    frigate.serverIp = ip
                    frigate.server = "http://" + ip + ":5000"

                    contentLoader.startupDone = true
                    contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"

                    // ⭐ Maximize = fullscreen
                    mainWindow.visibility = Window.FullScreen
                    mainWindow.showFullScreen()
                    topbar.isMaximized = true
                })
            }

            if (item.objectName !== "StartupPage" && discovery)
                discovery.stopDiscovery()

            if (item.objectName === "ServerView") {
                item.frigateRef = frigate
                item.mainWindow = mainWindow

                item.initializeGrid()
                frigate.loadCameras()

                item.camerasLoadedToMain.connect(function(list) {
                    mainWindow.cameraList = list
                    sidebarWrapper.cameraList = list
                })
            }
        }
    }

    //
    // Frigate Events
    //
    Connections {
        target: frigate

        function onCamerasLoaded(list) {
            mainWindow.cameraList = list
            sidebarWrapper.cameraList = list

            if (contentLoader.item &&
                contentLoader.item.objectName === "ServerView" &&
                contentLoader.item.updateCameras)
                contentLoader.item.updateCameras(list)

            mainWindow.camerasLoaded(list)
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

        function onCameraEditResult(ok, message) {
            if (ok) frigate.loadCameras()
        }

        function onCameraAddResult(ok, message) {
            if (ok) frigate.loadCameras()
        }
    }

    //
    // TopBar Window Controls
    //
    Connections {
        target: topbar

        function onDisconnectRequested() {
            contentLoader.startupDone = false
            contentLoader.source = "qrc:/app/resources/qml/StartupPage.qml"

            mainWindow.serverName = ""
            frigate.server = ""
            frigate.serverIp = ""

            // ⭐ Exit fullscreen → normal window
            mainWindow.showNormal()
            mainWindow.visibility = Window.Windowed

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

        //
        // ⭐ Maximize = fullscreen
        //
        function onMaximizeRequested() {
            mainWindow.visibility = Window.FullScreen
            mainWindow.showFullScreen()
            topbar.isMaximized = true
        }

        //
        // ⭐ Restore = normal window (1400×900)
        //
        function onRestoreRequested() {
            mainWindow.showNormal()
            mainWindow.visibility = Window.Windowed

            mainWindow.width = 1400
            mainWindow.height = 900
            mainWindow.x = (mainWindow.screen.width - mainWindow.width) / 2
            mainWindow.y = (mainWindow.screen.height - mainWindow.height) / 2

            topbar.isMaximized = false
        }
    }
}
