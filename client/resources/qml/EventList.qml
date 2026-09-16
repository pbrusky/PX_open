import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    objectName: "EventList"

    property var frigateRef
    property var mainWindow
    property string selectedCameraId: ""
    property bool collapsed: width < 20

    // false = selected camera only; true = all cameras
    property bool showAllCameras: true

    property var eventsModel: []
    property string statusText: ""

    signal requestToggleCollapse()

    clip: true

    function refresh() {
        if (root.width < 20)
            return
        if (!frigateRef || typeof frigateRef.loadEvents !== "function") {
            statusText = "No API"
            return
        }
        statusText = "Loading…"

        if (showAllCameras) {
            frigateRef.loadEvents("")   // empty = all cameras
            return
        }

        var cam = selectedCameraId && selectedCameraId.length ? selectedCameraId : ""
        if (cam.length) {
            frigateRef.loadEvents(cam)
            return
        }
        if (mainWindow && mainWindow.cameraList && mainWindow.cameraList.length) {
            var c0 = mainWindow.cameraList[0]
            var id0 = (typeof c0 === "string") ? c0 : (c0.id || c0.name || "")
            if (id0.length) {
                frigateRef.loadEvents(id0)
                return
            }
        }
        statusText = "Select a camera"
        eventsModel = []
    }

    onSelectedCameraIdChanged: {
        if (root.width >= 20 && !showAllCameras)
            Qt.callLater(refresh)
    }

    onShowAllCamerasChanged: {
        if (root.width >= 20)
            Qt.callLater(refresh)
    }

    onWidthChanged: {
        if (root.width >= 20)
            Qt.callLater(refresh)
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true
        enabled: frigateRef !== null && frigateRef !== undefined

        function onEventsLoaded(cameraId, list) {
            var rows = list
            if ((rows === undefined || rows === null) && cameraId !== undefined && cameraId !== null) {
                if (typeof cameraId === "object" && cameraId.length !== undefined)
                    rows = cameraId
            }
            root.eventsModel = rows || []
            root.statusText = root.eventsModel.length
                    ? (root.eventsModel.length + " events")
                    : "No events"
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#202020"
        visible: root.width > 0
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8
        visible: root.width > 40

        Item {
            width: parent.width
            height: 28

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Events"
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }

            Rectangle {
                id: refreshBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 24
                radius: 3
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: "Refresh"
                    color: "#ccc"
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        // All | Selected
        Row {
            spacing: 6
            Rectangle {
                width: 48
                height: 22
                radius: 3
                color: root.showAllCameras ? "#3A4A7A" : "#333"
                border.color: root.showAllCameras ? "#6A8AFF" : "#555"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "All"
                    color: "white"
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAllCameras = true
                }
            }
            Rectangle {
                width: 64
                height: 22
                radius: 3
                color: !root.showAllCameras ? "#3A4A7A" : "#333"
                border.color: !root.showAllCameras ? "#6A8AFF" : "#555"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "Selected"
                    color: "white"
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAllCameras = false
                }
            }
        }

        Text {
            width: parent.width
            text: root.showAllCameras
                  ? "All cameras"
                  : (root.selectedCameraId.length
                     ? ("Camera: " + root.selectedCameraId)
                     : "Select a camera")
            color: "#888"
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.statusText
            color: "#666"
            font.pixelSize: 11
        }

        ListView {
            id: list
            width: parent.width
            height: Math.max(50, col.height - 120)
            clip: true
            spacing: 8
            model: root.eventsModel

            delegate: Rectangle {
                id: rowRect
                width: list.width
                height: 72
                radius: 5
                color: delArea.containsMouse ? "#2A2A40" : "#1A1A1A"
                border.color: "#333"
                border.width: 1

                readonly property var row: (typeof modelData !== "undefined") ? modelData : model
                readonly property string evId: row && row.id ? ("" + row.id) : ""
                readonly property string evCamera: (row && row.camera) ? ("" + row.camera)
                                                                   : root.selectedCameraId
                readonly property string evLabel: (row && row.label) ? ("" + row.label) : "object"
                readonly property real evStart: {
                    if (!row)
                        return 0
                    if (row.start !== undefined && row.start !== null)
                        return Number(row.start)
                    if (row.start_time !== undefined && row.start_time !== null)
                        return Number(row.start_time)
                    return 0
                }
                readonly property real evScore: row && row.score !== undefined ? Number(row.score) : 0

                readonly property string thumbUrl: {
                    if (row && row.thumbnail) {
                        var t = "" + row.thumbnail
                        if (t.indexOf("data:") === 0)
                            return t
                        if (t.indexOf("http://") === 0 || t.indexOf("https://") === 0)
                            return t
                    }
                    if (!root.frigateRef || !evId.length)
                        return ""
                    var srv = ""
                    try {
                        srv = "" + (root.frigateRef.server || "")
                    } catch (e) {
                        return ""
                    }
                    if (!srv.length)
                        return ""
                    while (srv.length && srv.charAt(srv.length - 1) === "/")
                        srv = srv.substring(0, srv.length - 1)
                    return srv + "/api/events/" + evId + "/thumbnail.jpg"
                }

                function formatTs(sec) {
                    if (!sec || sec <= 0)
                        return ""
                    var d = new Date(sec * 1000)
                    return Qt.formatDateTime(d, "MM/dd hh:mm:ss")
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    Rectangle {
                        width: 96
                        height: 54
                        radius: 3
                        color: "#111"
                        clip: true

                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: rowRect.thumbUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: thumb.status !== Image.Ready
                            text: thumb.status === Image.Loading ? "…" : "No img"
                            color: "#666"
                            font.pixelSize: 11
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        width: Math.max(40, parent.width - 110)

                        Text {
                            text: rowRect.evLabel
                            color: "white"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Text {
                            text: rowRect.evCamera
                            color: "#aaa"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: rowRect.formatTs(rowRect.evStart)
                                  + (rowRect.evScore > 0
                                     ? ("  ·  " + Math.round(rowRect.evScore * 100) + "%")
                                     : "")
                            color: "#888"
                            font.pixelSize: 11
                        }
                    }
                }

                MouseArea {
                    id: delArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!rowRect.evCamera.length || rowRect.evStart <= 0)
                            return

                        // FFmpeg + CameraGrid fullscreen (same path as timeline seek)
                        if (root.mainWindow && typeof root.mainWindow.viewEvent === "function") {
                            root.mainWindow.viewEvent(rowRect.evCamera, rowRect.evStart)
                            return
                        }

                        // Fallback without MainWindow helper
                        if (root.frigateRef && typeof root.frigateRef.startPlayback === "function")
                            root.frigateRef.startPlayback(
                                        rowRect.evCamera,
                                        Math.floor(rowRect.evStart * 1000))
                    }
                }
            }
        }
    }
}