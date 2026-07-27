import PxOpen 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

import "qrc:/app/resources/qml/components"
import "qrc:/app/resources/qml/components/popups"

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

    property var fullscreenManager
    property var dropHandler

    signal cameraOnline(string name)
    signal cameraOffline(string name)
    signal camerasLoaded(var list)

    property bool isFullscreen: false

    function enterTrueFullscreen() {
        isFullscreen = true
        flags = Qt.FramelessWindowHint | Qt.Window
        showFullScreen()
    }

    function exitTrueFullscreen() {
        isFullscreen = false
        showNormal()
    }

    //
    // Extract username/password from RTSP URL (fallback)
    //
    function parseRtspCredentials(url) {
        if (!url || !url.startsWith("rtsp://"))
            return { user: "", pass: "" }

        let authPart = url.split("rtsp://")[1].split("@")[0]
        if (!authPart.includes(":"))
            return { user: "", pass: "" }

        let parts = authPart.split(":")
        return {
            user: parts[0],
            pass: parts[1]
        }
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

    Loader {
        id: fullscreenManagerLoader
        source: "qrc:/app/resources/qml/fullscreen/FullscreenManager.qml"
        asynchronous: false
        visible: false

        onLoaded: {
            var fm = fullscreenManagerLoader.item
            fm.mainWindow = mainWindow
            fm.frigateRef = frigateRef
            mainWindow.fullscreenManager = fm
        }
    }

    Loader {
        id: dropHandlerLoader
        source: "qrc:/app/resources/qml/components/CameraDropHandler.qml"
        asynchronous: false
        visible: false

        onLoaded: {
            var dh = dropHandlerLoader.item
            dh.mainWindow = mainWindow
            dh.contentLoader = contentLoader
            mainWindow.dropHandler = dh
        }
    }

    TopBar {
        id: topbar
        width: parent.width
        height: 48
        z: 9999

        property bool collapsed: false
        property bool isMaximized: false

        y: collapsed ? -height : 0
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        isStartupPage: contentLoader.item && contentLoader.item.objectName === "StartupPage"
        isCameraPage: contentLoader.item && contentLoader.item.objectName === "ServerView"
        serverName: mainWindow.serverName

        onAboutRequested: {
            popupManager.openPopup(
                "qrc:/app/resources/qml/components/popups/AboutPopup.qml",
                { mainWindow: mainWindow }
            )
        }

        onDisconnectRequested: {
            contentLoader.source = "qrc:/app/resources/qml/StartupPage.qml"
            mainWindow.serverName = ""
        }

        onExitRequested: Qt.quit()
        onMinimizeRequested: mainWindow.showMinimized()
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
            popupManager.openPopup(
                "qrc:/app/resources/qml/components/popups/RemoveCameraPopup.qml",
                {
                    frigateRef: frigateRef,
                    cameraId: id,
                    popupManager: popupManager
                }
            )
        }

        onCameraDropped: function(x, y, cameraName) {
            if (mainWindow.dropHandler)
                mainWindow.dropHandler.dropCamera(x, y, cameraName)
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
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/AddCameraPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager
                    }
                )
                return
            }

            if (page === "reloadCameras") {
                frigateRef.loadCameras()
                return
            }

            //
            // ⭐ FULLY PATCHED EDIT CAMERA BLOCK
            //
            if (page.startsWith("editCamera:")) {
                let camId = page.split(":")[1]
                let cam = mainWindow.cameraList.find(c => c.id === camId)

                if (cam) {
                    let rtsp = cam.rtsp || cam.streamUrl || ""
                    let user = cam.username || ""
                    let pass = cam.password || ""

                    // fallback: parse from RTSP if missing
                    if ((!user || !pass) && rtsp) {
                        let creds = parseRtspCredentials(rtsp)
                        if (!user) user = creds.user
                        if (!pass) pass = creds.pass
                    }

                    popupManager.openPopup(
                        "qrc:/app/resources/qml/components/popups/EditCameraPopup.qml",
                        {
                            frigateRef: frigateRef,
                            cameraId: cam.id,
                            cameraName: cam.name || "",
                            rtspUrl: rtsp,
                            username: user,
                            password: pass,
                            popupManager: popupManager
                        }
                    )
                } else {
                    console.log("EditCamera: Camera not found:", camId)
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

                    mainWindow.enterTrueFullscreen()
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

    Loader {
        id: connectionsLoader
        source: "qrc:/app/resources/qml/MainWindowConnections.qml"
        asynchronous: false
        visible: false

        onLoaded: {
            var c = connectionsLoader.item
            c.mainWindow = mainWindow
            c.frigateRef = frigateRef
            c.topbar = topbar
            c.sidebarWrapper = sidebarWrapper
            c.contentLoader = contentLoader
            c.restartPopup = restartPopup
            c.frigatePollTimer = frigatePollTimer
        }
    }

    RestartPopup {
        id: restartPopup
        frigateRef: mainWindow.frigateRef
        visible: false
        z: 999999
    }

    PopupManager {
        id: popupManager
        anchors.fill: parent
        z: 999999
    }
}
