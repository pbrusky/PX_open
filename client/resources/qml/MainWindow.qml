import PxOpen 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtCore

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
    property string pendingRemoveCameraId: ""
    property string serverName: ""
    property string _fullscreenCameraKey: ""

    property var fullscreenManager
    property var dropHandler

    signal cameraOnline(string name)
    signal cameraOffline(string name)
    signal camerasLoaded(var list)

    property bool isFullscreen: false

    // True while a camera is open in the fullscreen overlay (hide topbar/sidebar)
    property bool cameraFullscreenActive: false

    // After Disconnect, skip one auto-connect so user can stay on StartupPage
    property bool skipNextAutoConnect: false

    // ── Persist “restore last view in fullscreen” + last session ──
    Settings {
        id: appSettings
        category: "general"
        property bool restoreLastFullscreen: false
        property string lastServerName: ""
        property string lastServerIp: ""
        property int lastApiPort: 5000
        property int lastModulePort: 8001
    }

    function enterTrueFullscreen() {
        isFullscreen = true
        flags = Qt.FramelessWindowHint | Qt.Window
        showFullScreen()
    }

    function exitTrueFullscreen() {
        isFullscreen = false
        showNormal()
    }

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

    /** Collapse topbar + sidebar; user can reopen with the arrows. */
    function collapseChrome() {
        topbar.collapsed = true
        sidebarWrapper.collapsed = true
    }

    function noteUserActivity() {
        FullscreenHelper.noteUserActivity()
    }

    /** Called by CameraGrid when a camera enters fullscreen. */
    function rememberFullscreenCamera(cameraName) {
        if (!cameraName || cameraName === "")
            return
        if (frigateRef && frigateRef.serverIp)
            appSettings.lastServerIp = "" + frigateRef.serverIp
    }

    /**
     * Connect using saved server and jump straight to ServerView.
     * Returns true if auto-connect was started (StartupPage can be skipped).
     */
    function performAutoConnect() {
        if (!appSettings.restoreLastFullscreen)
            return false
        if (skipNextAutoConnect)
            return false

        var ip = appSettings.lastServerIp
        if (!ip || ("" + ip).length === 0)
            return false

        var apiPort = appSettings.lastApiPort > 0 ? appSettings.lastApiPort : 5000
        var modulePort = appSettings.lastModulePort > 0 ? appSettings.lastModulePort : 8001
        var name = (appSettings.lastServerName && appSettings.lastServerName.length)
                   ? appSettings.lastServerName
                   : "Frigate System"

        if (!frigateRef)
            return false

        if (typeof frigateRef.stopAllFullscreenStreams === "function")
            frigateRef.stopAllFullscreenStreams()
        if (typeof frigateRef.stopAllStreams === "function")
            frigateRef.stopAllStreams()

        mainWindow.cameraList = []
        mainWindow.selectedCameraId = ""
        if (sidebarWrapper)
            sidebarWrapper.cameraList = []

        mainWindow.serverName = name

        if (typeof frigateRef.setServerIp === "function")
            frigateRef.setServerIp(ip)
        else
            frigateRef.serverIp = ip

        if (typeof frigateRef.setServer === "function")
            frigateRef.setServer("http://" + ip + ":" + apiPort)
        else
            frigateRef.server = "http://" + ip + ":" + apiPort

        frigateRef.setModuleServer("http://" + ip + ":" + modulePort)

        contentLoader.startupDone = true
        contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"

        mainWindow.enterTrueFullscreen()
        topbar.isMaximized = true

        // Auto-collapse so grid uses full screen; arrows still expand chrome
        collapseChrome()

        return true
    }

    /** Leave Settings: back to Startup if not connected, else camera grid. */
    function leaveSettings() {
        if (contentLoader.startupDone)
            goToServerView()
        else
            goToStartupPage()
    }

    function goToServerView() {
        contentLoader.startupDone = true
        contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"
    }

    function goToStartupPage() {
        contentLoader.startupDone = false
        mainWindow.cameraFullscreenActive = false
        mainWindow.serverName = ""
        mainWindow.cameraList = []
        mainWindow.selectedCameraId = ""
        if (sidebarWrapper)
            sidebarWrapper.cameraList = []
        // Expand chrome again on disconnect / startup page
        topbar.collapsed = false
        sidebarWrapper.collapsed = false
        contentLoader.source = "qrc:/app/resources/qml/StartupPage.qml"
    }

    function disconnectFromServer() {
        // User left on purpose — do not auto-reconnect this time
        skipNextAutoConnect = true
        mainWindow.cameraFullscreenActive = false

        if (frigateRef) {
            if (typeof frigateRef.stopAllFullscreenStreams === "function")
                frigateRef.stopAllFullscreenStreams()
            if (typeof frigateRef.stopAllStreams === "function")
                frigateRef.stopAllStreams()
        }

        goToStartupPage()

        if (mainWindow.isFullscreen)
            mainWindow.exitTrueFullscreen()
        topbar.isMaximized = false
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            performAutoConnect()
        })
        FullscreenHelper.startIdleCursor(10000)
    }

    Connections {
        target: FullscreenHelper
        function onCursorHiddenChanged() {
            if (FullscreenHelper.cursorHidden)
                mainWindow.selectedCameraId = ""
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
        height: mainWindow.cameraFullscreenActive ? 0 : 48
        z: 9999
        visible: !mainWindow.cameraFullscreenActive
        opacity: mainWindow.cameraFullscreenActive ? 0 : 1

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

        onSettingsRequested: {
            contentLoader.source = "qrc:/app/resources/qml/generalSettings.qml"
        }

        onDisconnectRequested: {
            mainWindow.disconnectFromServer()
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

        visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
        onClicked: topbar.collapsed = !topbar.collapsed

        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }
    }

    Sidebar {
        id: sidebarWrapper
        objectName: "Sidebar"

        frigateRef: mainWindow.frigateRef

        width: 260
        height: mainWindow.height - (mainWindow.cameraFullscreenActive ? 0 : topbar.height)
        y: mainWindow.cameraFullscreenActive ? 0 : topbar.height
        z: 9998

        property bool collapsed: false

        x: collapsed ? -width : 0
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        visible: contentLoader.item && contentLoader.item.objectName === "ServerView"
                 && !mainWindow.cameraFullscreenActive

        cameraList: mainWindow.cameraList
        selectedCameraId: mainWindow.selectedCameraId
        serverName: mainWindow.serverName

        onCameraSelected: function(cameraId) {
            mainWindow.selectedCameraId = cameraId
        }

        onRequestRemoveCamera: function(id) {
            mainWindow.pendingRemoveCameraId = id
            var host = null
            if (contentLoader.item && contentLoader.item.objectName === "ServerView")
                host = contentLoader.item
            popupManager.openPopup(
                "qrc:/app/resources/qml/components/popups/RemoveCameraPopup.qml",
                {
                    frigateRef: frigateRef,
                    cameraId: id,
                    popupManager: popupManager,
                    gridHost: host
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
                mainWindow.disconnectFromServer()
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

            if (page === "editFrigateConfig") {
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/ConfigEditorPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager,
                        configType: "frigate"
                    }
                )
                return
            }

            if (page === "editGo2rtcConfig") {
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/ConfigEditorPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager,
                        configType: "go2rtc"
                    }
                )
                return
            }

            if (page === "saveLayout") {
                if (contentLoader.item && contentLoader.item.objectName === "ServerView"
                        && typeof contentLoader.item.saveLayout === "function") {
                    contentLoader.item.saveLayout()
                }
                return
            }

            if (page === "loadLayout") {
                if (contentLoader.item && contentLoader.item.objectName === "ServerView"
                        && typeof contentLoader.item.loadLayout === "function") {
                    contentLoader.item.loadLayout()
                }
                return
            }

            if (page === "reloadCameras") {
                frigateRef.loadCameras()
                return
            }

            if (page.startsWith("editCamera:")) {
                let camId = page.split(":")[1]
                let cam = mainWindow.cameraList.find(c => c.id === camId)

                if (cam) {
                    let rtsp = cam.rtsp || cam.streamUrl || ""
                    let user = cam.username || ""
                    let pass = cam.password || ""

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

        visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
        onClicked: sidebarWrapper.collapsed = !sidebarWrapper.collapsed

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        z: 2

        anchors.topMargin: (topbar.collapsed || mainWindow.cameraFullscreenActive) ? 0 : topbar.height
        anchors.leftMargin: (sidebarWrapper.collapsed || topbar.isStartupPage
                             || mainWindow.cameraFullscreenActive) ? 0 : sidebarWrapper.width

        property bool startupDone: false

        source: startupDone
                ? "qrc:/app/resources/qml/components/ServerView.qml"
                : "qrc:/app/resources/qml/StartupPage.qml"

        onLoaded: {
            if (!item) return

            if (item.objectName === "StartupPage") {
                item.discovery = discovery
                item.frigateRef = frigateRef

                if (appSettings.restoreLastFullscreen
                        && appSettings.lastServerIp
                        && appSettings.lastServerIp.length > 0
                        && !mainWindow.skipNextAutoConnect) {
                    Qt.callLater(function() {
                        if (!contentLoader.startupDone)
                            mainWindow.performAutoConnect()
                    })
                }
                mainWindow.skipNextAutoConnect = false

                item.serverSelected.connect(function(name, ip, apiPort, modulePort) {
                    if (frigateRef) {
                        if (typeof frigateRef.stopAllFullscreenStreams === "function")
                            frigateRef.stopAllFullscreenStreams()
                        if (typeof frigateRef.stopAllStreams === "function")
                            frigateRef.stopAllStreams()
                    }

                    mainWindow.cameraList = []
                    mainWindow.selectedCameraId = ""
                    if (sidebarWrapper)
                        sidebarWrapper.cameraList = []

                    mainWindow.serverName = name

                    appSettings.lastServerName = name || ""
                    appSettings.lastServerIp = ip || ""
                    appSettings.lastApiPort = apiPort || 5000
                    appSettings.lastModulePort = modulePort || 8001

                    if (typeof frigateRef.setServerIp === "function")
                        frigateRef.setServerIp(ip)
                    else
                        frigateRef.serverIp = ip

                    if (typeof frigateRef.setServer === "function")
                        frigateRef.setServer("http://" + ip + ":" + apiPort)
                    else
                        frigateRef.server = "http://" + ip + ":" + apiPort

                    frigateRef.setModuleServer("http://" + ip + ":" + modulePort)

                    contentLoader.startupDone = true
                    contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"

                    mainWindow.enterTrueFullscreen()
                    topbar.isMaximized = true
                })
            }

            if (item.objectName === "ServerView") {
                item.frigateRef = frigateRef
                item.mainWindow = mainWindow

                item.camerasLoadedToMain.connect(function(list) {
                    mainWindow.cameraList = list
                    sidebarWrapper.cameraList = list
                })

                item.initializeGrid()
                frigateRef.loadCameras()
            }
        }
    }

    PopupManager {
        id: popupManager
        anchors.fill: parent
        z: 999999
    }

    RestartPopup {
        id: restartPopup
        anchors.fill: parent
        frigateRef: mainWindow.frigateRef
        visible: false
        z: 2000000
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
            c.popupManager = popupManager
        }
    }
}