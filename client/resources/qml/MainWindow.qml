import PxOpen 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15

import "qrc:/app/resources/qml/components"
import "qrc:/app/resources/qml/components/popups"
import "qrc:/app/resources/qml/session"
import "qrc:/app/resources/qml/navigation"

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
    property bool cameraFullscreenActive: false

    property alias skipNextAutoConnect: session.skipNextAutoConnect
    property alias appSettings: session.settings

    function enterTrueFullscreen() {
        isFullscreen = true
        flags = Qt.FramelessWindowHint | Qt.Window
        showFullScreen()
    }

    function exitTrueFullscreen() {
        isFullscreen = false
        showNormal()
    }

    function noteUserActivity() {
        FullscreenHelper.noteUserActivity()
    }

    function collapseChrome() { session.collapseChrome() }
    function rememberFullscreenCamera(n) { session.rememberFullscreenCamera(n) }
    function syncSidebarLayouts() { session.syncSidebarLayouts() }
    function performAutoConnect() { return session.performAutoConnect() }
    function leaveSettings() { session.leaveSettings() }
    function goToServerView() { session.goToServerView() }
    function goToStartupPage() { session.goToStartupPage() }
    function disconnectFromServer() { session.disconnectFromServer() }

    readonly property bool onServerView: contentLoader.item
                                         && contentLoader.item.objectName === "ServerView"

    SessionManager {
        id: session
        mainWindow: mainWindow
        frigateRef: mainWindow.frigateRef
        contentLoader: contentLoader
        sidebar: sidebarWrapper
        topbar: topbar
        eventsPanel: eventsPanel
    }

    NavigationRouter {
        id: nav
        mainWindow: mainWindow
        frigateRef: mainWindow.frigateRef
        contentLoader: contentLoader
        sidebar: sidebarWrapper
        popupManager: popupManager
        session: session
    }

    Component.onCompleted: {
        Qt.callLater(function() { session.performAutoConnect() })
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
        isCameraPage: mainWindow.onServerView
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
        onDisconnectRequested: session.disconnectFromServer()
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

        visible: mainWindow.onServerView && !mainWindow.cameraFullscreenActive

        cameraList: mainWindow.cameraList
        selectedCameraId: mainWindow.selectedCameraId
        serverName: mainWindow.serverName

        onCameraSelected: function(cameraId) {
            mainWindow.selectedCameraId = cameraId
        }

        onRequestRemoveCamera: function(id) {
            mainWindow.pendingRemoveCameraId = id
            var host = null
            if (mainWindow.onServerView)
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
            nav.handle(page)
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

    EventList {
        id: eventsPanel
        objectName: "EventList"

        frigateRef: mainWindow.frigateRef
        mainWindow: mainWindow
        selectedCameraId: mainWindow.selectedCameraId

        property bool collapsed: true

        width: collapsed ? 0 : 300
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        height: mainWindow.height - (mainWindow.cameraFullscreenActive ? 0 : topbar.height)
        y: mainWindow.cameraFullscreenActive ? 0 : topbar.height
        anchors.right: parent.right
        z: 9998
        clip: true

        visible: mainWindow.onServerView && !mainWindow.cameraFullscreenActive

        // Wire the header collapse button from EventList.qml
        onRequestToggleCollapse: eventsPanel.collapsed = !eventsPanel.collapsed
    }

    IconButton {
    id: eventsArrow
    width: 32
    height: 32
    z: 10001

    // Mirror the sidebar behaviour:
    // - collapsed  → sit on the far right edge of the window
    // - open       → sit inside the left edge of the events panel
    x: eventsPanel.collapsed
        ? (mainWindow.width - width - 4)
        : (mainWindow.width - eventsPanel.width + 4)

    y: topbar.height + (mainWindow.height - topbar.height) / 2 - height / 2

    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    icon: eventsPanel.collapsed
          ? "qrc:/app/assets/icons/nx/arrow-left.svg"
          : "qrc:/app/assets/icons/nx/arrow-right.svg"

    visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
    onClicked: eventsPanel.collapsed = !eventsPanel.collapsed
}

    Loader {
        id: contentLoader
        anchors.fill: parent
        z: 2
        anchors.topMargin: (topbar.collapsed || mainWindow.cameraFullscreenActive) ? 0 : topbar.height
        anchors.leftMargin: (sidebarWrapper.collapsed || topbar.isStartupPage
                             || mainWindow.cameraFullscreenActive) ? 0 : sidebarWrapper.width
        anchors.rightMargin: (!eventsPanel.visible || eventsPanel.collapsed
                              || topbar.isStartupPage
                              || mainWindow.cameraFullscreenActive) ? 0 : 300

        property bool startupDone: false

        source: startupDone
                ? "qrc:/app/resources/qml/components/ServerView.qml"
                : "qrc:/app/resources/qml/StartupPage.qml"

        onLoaded: {
            if (!item)
                return
            if (item.objectName === "StartupPage")
                session.bindStartupPage(item)
            if (item.objectName === "ServerView")
                session.bindServerView(item)
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