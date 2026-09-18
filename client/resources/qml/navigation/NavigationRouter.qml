import QtQuick 2.15
import "qrc:/app/resources/qml/js/CameraUtils.js" as CameraUtils

Item {
    id: router

    property var mainWindow
    property var frigateRef
    property var contentLoader
    property var sidebar
    property var popupManager
    property var session   // SessionManager

    function serverView() {
        if (contentLoader && contentLoader.item
                && contentLoader.item.objectName === "ServerView")
            return contentLoader.item
        return null
    }

    function refreshLayouts() {
        var sv = serverView()
        if (!sv)
            return
        if (typeof sv.refreshLayouts === "function")
            sv.refreshLayouts()
        if (session && typeof session.syncSidebarLayouts === "function")
            session.syncSidebarLayouts()
        else if (sidebar)
            sidebar.layoutList = sv.savedLayouts || []
    }

    function handle(page) {
        if (!page)
            return true

        if (page === "qrc:/app/resources/qml/StartupPage.qml") {
            if (contentLoader) {
                contentLoader.startupDone = false
                contentLoader.source = page
            }
            return true
        }

        if (page === "disconnect") {
            if (session)
                session.disconnectFromServer()
            else if (mainWindow)
                mainWindow.disconnectFromServer()
            return true
        }

        if (page === "addCamera") {
            if (popupManager) {
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/AddCameraPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager
                    }
                )
            }
            return true
        }

        if (page === "editFrigateConfig") {
            if (popupManager) {
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/ConfigEditorPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager,
                        configType: "frigate"
                    }
                )
            }
            return true
        }

        if (page === "editGo2rtcConfig") {
            if (popupManager) {
                popupManager.openPopup(
                    "qrc:/app/resources/qml/components/popups/ConfigEditorPopup.qml",
                    {
                        frigateRef: frigateRef,
                        popupManager: popupManager,
                        configType: "go2rtc"
                    }
                )
            }
            return true
        }

        if (page.indexOf("saveLayoutAs:") === 0) {
            var saveName = page.substring("saveLayoutAs:".length)
            var svSave = serverView()
            if (svSave && typeof svSave.saveLayoutAs === "function") {
                svSave.saveLayoutAs(saveName)
                refreshLayouts()
                if (sidebar)
                    sidebar.selectedLayoutName = saveName
            }
            return true
        }

        if (page.indexOf("loadLayout:") === 0) {
            var loadName = page.substring("loadLayout:".length)
            var svLoad = serverView()
            if (svLoad && typeof svLoad.loadLayoutByName === "function") {
                svLoad.loadLayoutByName(loadName)
                if (sidebar)
                    sidebar.selectedLayoutName = loadName
            }
            return true
        }

        if (page.indexOf("deleteLayout:") === 0) {
            var delName = page.substring("deleteLayout:".length)
            var svDel = serverView()
            if (svDel && typeof svDel.deleteLayout === "function") {
                svDel.deleteLayout(delName)
                refreshLayouts()
                if (sidebar && sidebar.selectedLayoutName === delName)
                    sidebar.selectedLayoutName = ""
            }
            return true
        }

        if (page === "saveLayout") {
            var sv1 = serverView()
            if (sv1 && typeof sv1.saveLayout === "function") {
                sv1.saveLayout()
                refreshLayouts()
            }
            return true
        }

        if (page === "loadLayout") {
            var sv2 = serverView()
            if (sv2 && typeof sv2.loadLayout === "function")
                sv2.loadLayout()
            return true
        }

        if (page === "reloadCameras") {
            if (frigateRef)
                frigateRef.loadCameras()
            return true
        }

        if (page.indexOf("editCamera:") === 0) {
            var camId = page.substring("editCamera:".length)
            var list = mainWindow ? mainWindow.cameraList : []
            var cam = null
            for (var i = 0; i < list.length; i++) {
                if (list[i].id === camId) {
                    cam = list[i]
                    break
                }
            }
            if (cam && popupManager) {
                var rtsp = cam.rtsp || cam.streamUrl || ""
                var user = cam.username || ""
                var pass = cam.password || ""
                if ((!user || !pass) && rtsp) {
                    var creds = CameraUtils.parseRtspCredentials(rtsp)
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
            return true
        }

        // Fallback: treat as QML source path
        if (contentLoader && page.indexOf("qrc:") === 0)
            contentLoader.source = page

        return true
    }
}