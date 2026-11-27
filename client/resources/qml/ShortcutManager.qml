import QtQuick 2.15

QtObject {
    id: shortcuts

    property var mainWindow
    property var frigateRef
    property var contentLoader
    property var sidebar
    property var eventsPanel
    property var popupManager

    function serverView() {
        if (!contentLoader || !contentLoader.item)
            return null
        return contentLoader.item.objectName === "ServerView" ? contentLoader.item : null
    }

    function grid() {
        var sv = serverView()
        return sv ? sv.cameraGrid : null
    }

    function isTextEntry(item) {
        if (!item)
            return false
        if ("echoMode" in item)
            return true
        if ("textDocument" in item)
            return true
        if ("placeholderText" in item && "text" in item)
            return true
        return false
    }

    function stepCamera(direction) {
        var list = mainWindow.cameraList || []
        if (list.length === 0)
            return
        var current = "" + (mainWindow.selectedCameraId || "")
        var idx = -1
        for (var i = 0; i < list.length; i++) {
            var id = (typeof list[i] === "string") ? list[i] : (list[i].id || list[i].name || "")
            if (id === current || ("" + (list[i].name || "")) === current) {
                idx = i
                break
            }
        }
        idx = (idx + direction + list.length) % list.length
        var cam = list[idx]
        var nextId = (typeof cam === "string") ? cam : (cam.id || cam.name || "")
        mainWindow.selectedCameraId = nextId
        var g = grid()
        if (g && typeof g.addCamera === "function" && !mainWindow.cameraFullscreenActive)
            g.addCamera(nextId)
    }

    function selectByIndex(index) {
        var list = mainWindow.cameraList || []
        if (index < 0 || index >= list.length)
            return
        var cam = list[index]
        var id = (typeof cam === "string") ? cam : (cam.id || cam.name || "")
        mainWindow.selectedCameraId = id
        var g = grid()
        if (g && typeof g.addCamera === "function" && !mainWindow.cameraFullscreenActive)
            g.addCamera(id)
    }

    function toggleFullscreen() {
        var g = grid()
        if (!g)
            return
        if (mainWindow.cameraFullscreenActive) {
            if (typeof g.exitFullscreen === "function")
                g.exitFullscreen()
        } else if (mainWindow.selectedCameraId && typeof g.enterFullscreen === "function") {
            g.enterFullscreen(mainWindow.selectedCameraId)
        }
    }

    function goLive() {
        var g = grid()
        if (g && typeof g.goLive === "function") {
            g.goLive()
            return
        }
        if (frigateRef && mainWindow.selectedCameraId
                && typeof frigateRef.switchToLive === "function")
            frigateRef.switchToLive(mainWindow.selectedCameraId)
    }

    function toggleTimeline() {
        var sv = serverView()
        if (sv)
            sv.timelineCollapsed = !sv.timelineCollapsed
    }

    function handleKey(key, modifiers) {
        var event = {
            key: key,
            modifiers: (modifiers === undefined) ? Qt.NoModifier : modifiers,
            accepted: false
        }
        handle(event)
    }

    function handle(event) {
        if (!mainWindow || isTextEntry(mainWindow.activeFocusItem))
            return

        var key = event.key
        var mods = event.modifiers || Qt.NoModifier

        if (popupManager && popupManager.currentPopup) {
            if (key === Qt.Key_Escape)
                popupManager.closePopup()
            if (key !== Qt.Key_Escape)
                return
            event.accepted = true
            return
        }

        var g = grid()

        if (key === Qt.Key_Escape) {
            if (mainWindow.cameraFullscreenActive && g && typeof g.exitFullscreen === "function") {
                g.exitFullscreen()
                event.accepted = true
            }
            return
        }

        if (key === Qt.Key_F1 || key === Qt.Key_Question) {
            if (popupManager)
                popupManager.openPopup("qrc:/app/resources/qml/components/popups/ShortcutHelpPopup.qml", {})
            event.accepted = true
            return
        }

        if (key === Qt.Key_F || key === Qt.Key_F11) {
            toggleFullscreen()
            event.accepted = true
            return
        }

        if (key === Qt.Key_L) {
            goLive()
            event.accepted = true
            return
        }

        if (key === Qt.Key_Tab) {
            if (mods & Qt.ControlModifier)
                toggleTimeline()
            else if (mods & Qt.ShiftModifier) {
                if (eventsPanel)
                    eventsPanel.collapsed = !eventsPanel.collapsed
            } else if (sidebar) {
                sidebar.collapsed = !sidebar.collapsed
            }
            event.accepted = true
            return
        }

        if (key === Qt.Key_E) {
            if (eventsPanel)
                eventsPanel.collapsed = !eventsPanel.collapsed
            event.accepted = true
            return
        }

        if (key === Qt.Key_T) {
            toggleTimeline()
            event.accepted = true
            return
        }

        if (key === Qt.Key_G) {
            if (typeof mainWindow.goToServerView === "function")
                mainWindow.goToServerView()
            event.accepted = true
            return
        }

        if (key === Qt.Key_H) {
            if (typeof mainWindow.goToStartupPage === "function")
                mainWindow.goToStartupPage()
            event.accepted = true
            return
        }

        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            var delta = (key === Qt.Key_Left ? -10 : 10) * 1000
            if (mainWindow.cameraFullscreenActive && g && typeof g.seekRelative === "function") {
                if (g.seekRelative(delta)) {
                    event.accepted = true
                    return
                }
            }
            stepCamera(key === Qt.Key_Right ? 1 : -1)
            event.accepted = true
            return
        }

        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            stepCamera(key === Qt.Key_Down ? 1 : -1)
            event.accepted = true
            return
        }

        if (key >= Qt.Key_1 && key <= Qt.Key_9) {
            selectByIndex(key - Qt.Key_1)
            event.accepted = true
            return
        }
        if (key === Qt.Key_0) {
            selectByIndex(9)
            event.accepted = true
            return
        }

        if (key === Qt.Key_S && (mods & Qt.ControlModifier)) {
            var sv = serverView()
            if (sv && typeof sv.saveLayout === "function")
                sv.saveLayout()
            event.accepted = true
        }
    }
}
