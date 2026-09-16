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

    property bool showAllCameras: true

    property var eventsRaw: []
    property var eventsModel: []
    property string statusText: ""

    // Filters
    property string filterLabel: ""       // "" = all labels
    property real filterMinScore: 0       // 0..1
    property int filterHours: 24          // 6, 24, 72, 168

    signal requestToggleCollapse()

    clip: true

    function cameraForRequest() {
        if (showAllCameras)
            return ""
        var cam = selectedCameraId && selectedCameraId.length ? selectedCameraId : ""
        if (cam.length)
            return cam
        if (mainWindow && mainWindow.cameraList && mainWindow.cameraList.length) {
            var c0 = mainWindow.cameraList[0]
            return (typeof c0 === "string") ? c0 : (c0.id || c0.name || "")
        }
        return ""
    }

    function refresh() {
        if (root.width < 20)
            return
        if (!frigateRef) {
            statusText = "No API"
            return
        }

        var cam = cameraForRequest()
        if (!showAllCameras && !cam.length) {
            statusText = "Select a camera"
            eventsRaw = []
            eventsModel = []
            return
        }

        statusText = "Loading…"

        var nowSec = Math.floor(Date.now() / 1000)
        var afterSec = nowSec - (filterHours * 3600)

        if (typeof frigateRef.loadEventsRange === "function") {
            frigateRef.loadEventsRange(cam, afterSec, nowSec)
            return
        }
        if (typeof frigateRef.loadEvents === "function") {
            frigateRef.loadEvents(cam)
            return
        }
        statusText = "No API"
    }

    function applyFilters() {
        var src = eventsRaw || []
        var out = []
        var labelWant = (filterLabel || "").toLowerCase()

        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            if (!row)
                continue

            var label = (row.label !== undefined && row.label !== null) ? ("" + row.label) : "object"
            if (labelWant.length && label.toLowerCase() !== labelWant)
                continue

            var score = row.score !== undefined ? Number(row.score) : 0
            if (filterMinScore > 0 && score < filterMinScore)
                continue

            out.push(row)
        }

        eventsModel = out
        var parts = []
        parts.push(out.length + " of " + src.length)
        if (filterLabel.length)
            parts.push(filterLabel)
        if (filterMinScore > 0)
            parts.push(">=" + Math.round(filterMinScore * 100) + "%")
        parts.push(formatHoursChip(filterHours))
        statusText = src.length ? parts.join(" · ") : "No events"
    }

    function formatHoursChip(h) {
        if (h < 24)
            return h + "h"
        if (h % 24 === 0)
            return (h / 24) + "d"
        return h + "h"
    }

    function availableLabels() {
        var map = ({})
        var src = eventsRaw || []
        for (var i = 0; i < src.length; i++) {
            var row = src[i]
            if (!row)
                continue
            var lab = (row.label !== undefined && row.label !== null) ? ("" + row.label) : "object"
            if (lab.length)
                map[lab] = true
        }
        var keys = Object.keys(map)
        keys.sort()
        return keys
    }

    function rebuildLabelModel() {
        var prev = root.filterLabel
        labelModel.clear()
        labelModel.append({ text: "All labels", value: "" })
        var labs = root.availableLabels()
        var selectIdx = 0
        for (var i = 0; i < labs.length; i++) {
            labelModel.append({ text: labs[i], value: labs[i] })
            if (prev.length && labs[i] === prev)
                selectIdx = i + 1
        }
        Qt.callLater(function() {
            if (labelCombo.count > 0) {
                labelCombo.currentIndex = selectIdx
                if (selectIdx === 0)
                    root.filterLabel = ""
            }
        })
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
        if (root.width >= 20) {
            rebuildLabelModel()
            Qt.callLater(refresh)
        }
    }
    onFilterLabelChanged: applyFilters()
    onFilterMinScoreChanged: applyFilters()
    onFilterHoursChanged: {
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
            root.eventsRaw = rows || []
            root.applyFilters()
            root.rebuildLabelModel()
        }
    }

    ListModel {
        id: labelModel
        Component.onCompleted: {
            clear()
            append({ text: "All labels", value: "" })
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

        Row {
            spacing: 6
            Rectangle {
                width: 48; height: 22; radius: 3
                color: root.showAllCameras ? "#3A4A7A" : "#333"
                border.color: root.showAllCameras ? "#6A8AFF" : "#555"
                border.width: 1
                Text { anchors.centerIn: parent; text: "All"; color: "white"; font.pixelSize: 11 }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAllCameras = true
                }
            }
            Rectangle {
                width: 64; height: 22; radius: 3
                color: !root.showAllCameras ? "#3A4A7A" : "#333"
                border.color: !root.showAllCameras ? "#6A8AFF" : "#555"
                border.width: 1
                Text { anchors.centerIn: parent; text: "Selected"; color: "white"; font.pixelSize: 11 }
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

        ComboBox {
            id: labelCombo
            width: parent.width
            height: 28
            model: labelModel
            textRole: "text"
            currentIndex: 0
            font.pixelSize: 12
            background: Rectangle {
                color: "#2A2A2A"
                radius: 4
                border.color: "#444"
            }
            contentItem: Text {
                text: labelCombo.displayText.length
                      ? labelCombo.displayText
                      : "All labels"
                color: "white"
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
                elide: Text.ElideRight
            }
            onActivated: {
                if (currentIndex < 0 || currentIndex >= labelModel.count) {
                    root.filterLabel = ""
                    return
                }
                var item = labelModel.get(currentIndex)
                root.filterLabel = item ? (item.value || "") : ""
            }
            Component.onCompleted: {
                if (labelModel.count === 0)
                    labelModel.append({ text: "All labels", value: "" })
                currentIndex = 0
                root.filterLabel = ""
            }
        }

        Row {
            spacing: 4
            Repeater {
                model: [
                    { t: "Any", v: 0 },
                    { t: "50%+", v: 0.5 },
                    { t: "70%+", v: 0.7 },
                    { t: "90%+", v: 0.9 }
                ]
                delegate: Rectangle {
                    width: scoreLabel.implicitWidth + 12
                    height: 22
                    radius: 3
                    color: Math.abs(root.filterMinScore - modelData.v) < 0.01 ? "#3A4A7A" : "#333"
                    border.color: Math.abs(root.filterMinScore - modelData.v) < 0.01 ? "#6A8AFF" : "#555"
                    border.width: 1
                    Text {
                        id: scoreLabel
                        anchors.centerIn: parent
                        text: modelData.t
                        color: "white"
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.filterMinScore = modelData.v
                    }
                }
            }
        }

        Row {
            spacing: 4
            Repeater {
                model: [
                    { t: "6h", v: 6 },
                    { t: "1 day", v: 24 },
                    { t: "3 days", v: 72 },
                    { t: "7 days", v: 168 }
                ]
                delegate: Rectangle {
                    width: timeLabel.implicitWidth + 12
                    height: 22
                    radius: 3
                    color: root.filterHours === modelData.v ? "#3A4A7A" : "#333"
                    border.color: root.filterHours === modelData.v ? "#6A8AFF" : "#555"
                    border.width: 1
                    Text {
                        id: timeLabel
                        anchors.centerIn: parent
                        text: modelData.t
                        color: "white"
                        font.pixelSize: 11
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.filterHours = modelData.v
                    }
                }
            }
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
            height: Math.max(50, col.height - 200)
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
                    if (!row) return 0
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
                        if (t.indexOf("data:") === 0 || t.indexOf("http") === 0)
                            return t
                    }
                    if (!root.frigateRef || !evId.length)
                        return ""
                    var srv = ""
                    try { srv = "" + (root.frigateRef.server || "") } catch (e) { return "" }
                    if (!srv.length) return ""
                    while (srv.length && srv.charAt(srv.length - 1) === "/")
                        srv = srv.substring(0, srv.length - 1)
                    return srv + "/api/events/" + evId + "/thumbnail.jpg"
                }

                function formatTs(sec) {
                    if (!sec || sec <= 0) return ""
                    return Qt.formatDateTime(new Date(sec * 1000), "MM/dd hh:mm:ss")
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10
                    Rectangle {
                        width: 96; height: 54; radius: 3; color: "#111"; clip: true
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
                        if (root.mainWindow && typeof root.mainWindow.viewEvent === "function") {
                            root.mainWindow.viewEvent(rowRect.evCamera, rowRect.evStart)
                            return
                        }
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