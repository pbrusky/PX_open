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

    // Avoid duplicate timeline prefetch for the same camera
    property string _timelinePrefetchCam: ""

    property var fullscreenManager
    property var dropHandler

    signal cameraOnline(string name)
    signal cameraOffline(string name)
    signal camerasLoaded(var list)

    property bool isFullscreen: false
    property bool cameraFullscreenActive: false

    // Used only so sidebar/events stop above the full-width timeline when expanded.
    // contentLoader does NOT use this as bottomMargin (avoids gap under timeline).
    readonly property real gridTimelineReserve: {
        if (!onServerView || cameraFullscreenActive)
            return 0
        var sv = contentLoader.item
        if (sv && sv.timelineBarHeight !== undefined)
            return Number(sv.timelineBarHeight) || 0
        return 0
    }

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

    function clearTimelinePrefetch() {
        _timelinePrefetchCam = ""
    }

    // Warm timeline caches on the grid: recordings + motion ticks only.
    // Events load only when the Events panel is open (EventList.refresh).
    function prefetchTimelineForCamera(cameraId) {
        if (!frigateRef || !cameraId || !(("" + cameraId).length))
            return
        if (!onServerView)
            return

        var id = "" + cameraId
        if (id === _timelinePrefetchCam)
            return
        _timelinePrefetchCam = id

        if (typeof frigateRef.loadRecordingDays === "function")
            frigateRef.loadRecordingDays(id)

        var nowSec = Math.floor(Date.now() / 1000)
        var afterSec = nowSec - (6 * 3600)

        if (typeof frigateRef.loadRecordingsRange === "function")
            frigateRef.loadRecordingsRange(id, afterSec, nowSec)
        else if (typeof frigateRef.loadRecordings === "function")
            frigateRef.loadRecordings(id)

        // Motion ticks on the timeline
        if (typeof frigateRef.loadMotionActivityRange === "function")
            frigateRef.loadMotionActivityRange(id, afterSec, nowSec)
        else if (typeof frigateRef.loadMotionActivity === "function")
            frigateRef.loadMotionActivity(id)

        // Do NOT load events here — EventList does that when the panel is open
    }

    onSelectedCameraIdChanged: {
        if (!selectedCameraId || !selectedCameraId.length)
            return
        Qt.callLater(function() {
            mainWindow.prefetchTimelineForCamera(mainWindow.selectedCameraId)
        })
    }

    function viewEvent(cameraId, startSec) {
        if (!cameraId || !(("" + cameraId).length))
            return

        var sec = Number(startSec)
        if (!(sec > 0))
            return

        var ms = Math.floor(sec * 1000)
        var name = "" + cameraId

        prefetchTimelineForCamera(name)

        var sv = null
        if (contentLoader.item && contentLoader.item.objectName === "ServerView")
            sv = contentLoader.item

        if (sv && sv.cameraGrid) {
            if (typeof sv.cameraGrid.enterFullscreenAndSeek === "function") {
                sv.cameraGrid.enterFullscreenAndSeek(name, ms)
                return
            }
            if (typeof sv.cameraGrid.enterFullscreen === "function") {
                sv.cameraGrid.enterFullscreen(name)
                return
            }
        }

        if (frigateRef && typeof frigateRef.startPlayback === "function")
            frigateRef.startPlayback(name, ms)
    }

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

    // Grid between sidebar and events; margins track live panel widths.
    Loader {
        id: contentLoader
        anchors.fill: parent
        z: 2
        anchors.topMargin: (topbar.collapsed || mainWindow.cameraFullscreenActive) ? 0 : topbar.height

        anchors.leftMargin: (topbar.isStartupPage || mainWindow.cameraFullscreenActive)
                            ? 0
                            : (sidebarWrapper.collapsed ? 0 : sidebarWrapper.width)

        anchors.rightMargin: (topbar.isStartupPage || mainWindow.cameraFullscreenActive)
                             ? 0
                             : eventsPanel.width

        Behavior on anchors.leftMargin {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
        Behavior on anchors.rightMargin {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }

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

    // High-visibility top pull-tab handle for TopBar
    Rectangle {
        id: topbarArrow
        width: 44
        height: 24
        radius: 6
        color: topbarArrowArea.containsMouse ? "#3A3A4D" : "#1B1B22"
        border.color: topbarArrowArea.containsMouse ? "#6A8AFF" : "#4A4A58"
        border.width: 1.5
        z: 10000

        x: (mainWindow.width / 2) - (width / 2)
        y: topbar.collapsed ? -2 : (topbar.height - (height / 2))
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: topbar.collapsed
                  ? "qrc:/app/assets/icons/nx/arrow-down.svg"
                  : "qrc:/app/assets/icons/nx/arrow-up.svg"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: topbarArrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: topbar.collapsed = !topbar.collapsed
        }

        visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
    }

    Sidebar {
        id: sidebarWrapper
        objectName: "Sidebar"
        frigateRef: mainWindow.frigateRef
        width: 260
        height: {
            var top = mainWindow.cameraFullscreenActive ? 0 : topbar.height
            return mainWindow.height - top - mainWindow.gridTimelineReserve
        }
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

    // High-visibility side handle tab for the Sidebar
    Rectangle {
        id: sidebarReturnArrow
        width: 32
        height: 44
        radius: 8
        color: sidebarArrowArea.containsMouse ? "#3A3A4D" : "#1B1B22"
        border.color: sidebarArrowArea.containsMouse ? "#6A8AFF" : "#4A4A58"
        border.width: 1.5
        z: 10001

        x: sidebarWrapper.collapsed
            ? -4
            : (sidebarWrapper.x + sidebarWrapper.width - (width / 2))

        y: topbar.height + (mainWindow.height - topbar.height - mainWindow.gridTimelineReserve) / 2 - height / 2

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: sidebarWrapper.collapsed
                  ? "qrc:/app/assets/icons/nx/arrow-right.svg"
                  : "qrc:/app/assets/icons/nx/arrow-left.svg"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: sidebarArrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sidebarWrapper.collapsed = !sidebarWrapper.collapsed
        }

        visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
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

        height: {
            var top = mainWindow.cameraFullscreenActive ? 0 : topbar.height
            return mainWindow.height - top - mainWindow.gridTimelineReserve
        }
        y: mainWindow.cameraFullscreenActive ? 0 : topbar.height
        anchors.right: parent.right
        z: 9998
        clip: true

        visible: mainWindow.onServerView && !mainWindow.cameraFullscreenActive

        onRequestToggleCollapse: eventsPanel.collapsed = !eventsPanel.collapsed
    }

    // High-visibility side handle tab for the Events Panel
    Rectangle {
        id: eventsArrow
        width: 32
        height: 44
        radius: 8
        color: eventsArrowArea.containsMouse ? "#3A3A4D" : "#1B1B22"
        border.color: eventsArrowArea.containsMouse ? "#6A8AFF" : "#4A4A58"
        border.width: 1.5
        z: 10001

        x: eventsPanel.collapsed
            ? (mainWindow.width - width + 4)
            : (mainWindow.width - eventsPanel.width - (width / 2))

        y: topbar.height + (mainWindow.height - topbar.height - mainWindow.gridTimelineReserve) / 2 - height / 2

        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: eventsPanel.collapsed
                  ? "qrc:/app/assets/icons/nx/arrow-left.svg"
                  : "qrc:/app/assets/icons/nx/arrow-right.svg"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: eventsArrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: eventsPanel.collapsed = !eventsPanel.collapsed
        }

        visible: !topbar.isStartupPage && !mainWindow.cameraFullscreenActive
    }

    // High-visibility bottom pull-tab handle for the Timeline
    Rectangle {
        id: timelineArrow
        width: 44
        height: 24
        radius: 6
        color: timelineArrowArea.containsMouse ? "#3A3A4D" : "#1B1B22"
        border.color: timelineArrowArea.containsMouse ? "#6A8AFF" : "#4A4A58"
        border.width: 1.5
        z: 10000

        x: (mainWindow.width / 2) - (width / 2)
        y: mainWindow.gridTimelineReserve > 0
            ? (mainWindow.height - mainWindow.gridTimelineReserve - (height / 2))
            : (mainWindow.height - height + 2)

        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: mainWindow.gridTimelineReserve > 0
                  ? "qrc:/app/assets/icons/nx/arrow-down.svg"
                  : "qrc:/app/assets/icons/nx/arrow-up.svg"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: timelineArrowArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                var sv = contentLoader.item
                if (!sv)
                    return
                if (typeof sv.toggleTimeline === "function") {
                    sv.toggleTimeline()
                } else if (sv.timeline && sv.timeline.collapsed !== undefined) {
                    sv.timeline.collapsed = !sv.timeline.collapsed
                } else if (sv.timelineCollapsed !== undefined) {
                    sv.timelineCollapsed = !sv.timelineCollapsed
                }
            }
        }

        visible: mainWindow.onServerView && !mainWindow.cameraFullscreenActive
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