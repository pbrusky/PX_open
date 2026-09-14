import QtQuick 2.15
import QtCore

Item {
    id: session

    property var mainWindow
    property var frigateRef
    property var contentLoader
    property var sidebar
    property var topbar
    property var eventsPanel

    property bool skipNextAutoConnect: false

    Settings {
        id: appSettings
        category: "general"
        property bool restoreLastFullscreen: false
        property string lastServerName: ""
        property string lastServerIp: ""
        property int lastApiPort: 5000
        property int lastModulePort: 8001
    }

    property alias settings: appSettings

    function collapseChrome() {
        if (topbar)
            topbar.collapsed = true
        if (sidebar)
            sidebar.collapsed = true
        if (eventsPanel)
            eventsPanel.collapsed = true
    }

    function expandChrome() {
        if (topbar)
            topbar.collapsed = false
        if (sidebar)
            sidebar.collapsed = false
        // Events stay collapsed by default on startup page (panel hidden anyway)
        if (eventsPanel)
            eventsPanel.collapsed = true
    }

    function rememberFullscreenCamera(cameraName) {
        if (!cameraName || cameraName === "")
            return
        if (frigateRef && frigateRef.serverIp)
            appSettings.lastServerIp = "" + frigateRef.serverIp
    }

    function syncSidebarLayouts() {
        if (!sidebar || !contentLoader || !contentLoader.item)
            return
        if (contentLoader.item.objectName === "ServerView")
            sidebar.layoutList = contentLoader.item.savedLayouts || []
    }

    function stopAllStreams() {
        if (!frigateRef)
            return
        if (typeof frigateRef.stopAllFullscreenStreams === "function")
            frigateRef.stopAllFullscreenStreams()
        if (typeof frigateRef.stopAllStreams === "function")
            frigateRef.stopAllStreams()
    }

    function applyServerEndpoints(name, ip, apiPort, modulePort) {
        if (mainWindow)
            mainWindow.serverName = name || ""

        appSettings.lastServerName = name || ""
        appSettings.lastServerIp = ip || ""
        appSettings.lastApiPort = apiPort || 5000
        appSettings.lastModulePort = modulePort || 8001

        if (!frigateRef)
            return

        if (typeof frigateRef.setServerIp === "function")
            frigateRef.setServerIp(ip)
        else
            frigateRef.serverIp = ip

        var api = "http://" + ip + ":" + (apiPort || 5000)
        if (typeof frigateRef.setServer === "function")
            frigateRef.setServer(api)
        else
            frigateRef.server = api

        frigateRef.setModuleServer("http://" + ip + ":" + (modulePort || 8001))
    }

    function clearClientState() {
        if (mainWindow) {
            mainWindow.cameraList = []
            mainWindow.selectedCameraId = ""
            mainWindow.cameraFullscreenActive = false
        }
        if (sidebar) {
            sidebar.cameraList = []
            sidebar.layoutList = []
            sidebar.selectedLayoutName = ""
        }
    }

    function goToServerView() {
        if (!contentLoader)
            return
        contentLoader.startupDone = true
        contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"
    }

    function goToStartupPage() {
        if (!contentLoader)
            return
        contentLoader.startupDone = false
        if (mainWindow) {
            mainWindow.cameraFullscreenActive = false
            mainWindow.serverName = ""
            mainWindow.cameraList = []
            mainWindow.selectedCameraId = ""
        }
        if (sidebar) {
            sidebar.cameraList = []
            sidebar.layoutList = []
            sidebar.selectedLayoutName = ""
        }
        expandChrome()
        contentLoader.source = "qrc:/app/resources/qml/StartupPage.qml"
    }

    function leaveSettings() {
        if (contentLoader && contentLoader.startupDone)
            goToServerView()
        else
            goToStartupPage()
    }

    function onServerSelected(name, ip, apiPort, modulePort) {
        stopAllStreams()
        clearClientState()
        applyServerEndpoints(name, ip, apiPort, modulePort)

        if (contentLoader) {
            contentLoader.startupDone = true
            contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"
        }

        if (mainWindow) {
            mainWindow.enterTrueFullscreen()
            if (topbar)
                topbar.isMaximized = true
            // Same kiosk chrome as auto-connect
            collapseChrome()
        }
    }

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

        stopAllStreams()
        clearClientState()
        applyServerEndpoints(name, ip, apiPort, modulePort)

        if (contentLoader) {
            contentLoader.startupDone = true
            contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"
        }

        if (mainWindow) {
            mainWindow.enterTrueFullscreen()
            if (topbar)
                topbar.isMaximized = true
            collapseChrome()
        }
        return true
    }

    function disconnectFromServer() {
        skipNextAutoConnect = true
        if (mainWindow)
            mainWindow.cameraFullscreenActive = false

        stopAllStreams()
        goToStartupPage()

        if (mainWindow && mainWindow.isFullscreen)
            mainWindow.exitTrueFullscreen()
        if (topbar)
            topbar.isMaximized = false
    }

    function bindStartupPage(item) {
        if (!item)
            return

        item.discovery = (typeof discovery !== "undefined") ? discovery : item.discovery
        item.frigateRef = frigateRef

        if (appSettings.restoreLastFullscreen
                && appSettings.lastServerIp
                && appSettings.lastServerIp.length > 0
                && !skipNextAutoConnect) {
            Qt.callLater(function() {
                if (contentLoader && !contentLoader.startupDone)
                    performAutoConnect()
            })
        }
        skipNextAutoConnect = false

        item.serverSelected.connect(function(name, ip, apiPort, modulePort) {
            onServerSelected(name, ip, apiPort, modulePort)
        })
    }

    function bindServerView(item) {
        if (!item || !mainWindow)
            return

        item.frigateRef = frigateRef
        item.mainWindow = mainWindow

        item.camerasLoadedToMain.connect(function(list) {
            mainWindow.cameraList = list
            if (sidebar)
                sidebar.cameraList = list
        })

        if (item.layoutsChanged) {
            item.layoutsChanged.connect(function() {
                syncSidebarLayouts()
            })
        }

        item.initializeGrid()
        if (frigateRef)
            frigateRef.loadCameras()

        Qt.callLater(function() {
            if (typeof item.refreshLayouts === "function")
                item.refreshLayouts()
            syncSidebarLayouts()
            // Keep events closed after view bind in kiosk-style sessions
            if (eventsPanel)
                eventsPanel.collapsed = true
        })
    }
}