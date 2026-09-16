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

    property string filterLabel: ""
    property real filterMinScore: 0
    property int filterHours: 24

    signal requestToggleCollapse()

    readonly property color accent: "#6A8AFF"
    readonly property color panelBg: "#1B1B1F"
    readonly property color cardBg: "#25252B"
    readonly property color cardHover: "#2E2E38"
    readonly property color chipIdle: "#2A2A32"
    readonly property color chipActive: "#2F3A5C"
    readonly property color muted: "#8A8A96"
    readonly property color softBorder: "#3A3A44"

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

    function labelColor(name) {
        var n = (name || "").toLowerCase()
        if (n.indexOf("person") >= 0) return "#5B9CFF"
        if (n.indexOf("car") >= 0 || n.indexOf("vehicle") >= 0) return "#FFB020"
        if (n.indexOf("dog") >= 0 || n.indexOf("cat") >= 0 || n.indexOf("animal") >= 0) return "#5AD67D"
        if (n.indexOf("bicycle") >= 0 || n.indexOf("bike") >= 0) return "#C084FC"
        return "#9AA3B2"
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

    // Background
    Rectangle {
        anchors.fill: parent
        color: root.panelBg
        visible: root.width > 0

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: root.softBorder
        }
    }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10
        visible: root.width > 40

        // Header
        Item {
            width: parent.width
            height: 30

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Events"
                color: "#F2F2F5"
                font.pixelSize: 17
                font.bold: true
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: refreshLabel.implicitWidth + 16
                height: 26
                radius: 13
                color: refreshArea.containsMouse ? "#3A3A48" : root.chipIdle
                border.color: root.softBorder
                border.width: 1

                Text {
                    id: refreshLabel
                    anchors.centerIn: parent
                    text: "Refresh"
                    color: "#D0D0D8"
                    font.pixelSize: 11
                }
                MouseArea {
                    id: refreshArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.softBorder
        }

        // All / Selected
        Row {
            spacing: 6

            Rectangle {
                width: 52
                height: 26
                radius: 13
                color: root.showAllCameras ? root.chipActive : root.chipIdle
                border.color: root.showAllCameras ? root.accent : root.softBorder
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "All"
                    color: "white"
                    font.pixelSize: 11
                    font.bold: root.showAllCameras
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showAllCameras = true
                }
            }
            Rectangle {
                width: 72
                height: 26
                radius: 13
                color: !root.showAllCameras ? root.chipActive : root.chipIdle
                border.color: !root.showAllCameras ? root.accent : root.softBorder
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "Selected"
                    color: "white"
                    font.pixelSize: 11
                    font.bold: !root.showAllCameras
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
            color: root.muted
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        // Label filter
        ComboBox {
            id: labelCombo
            width: parent.width
            height: 30
            model: labelModel
            textRole: "text"
            currentIndex: 0
            font.pixelSize: 12
            background: Rectangle {
                color: root.chipIdle
                radius: 8
                border.color: root.softBorder
            }
            contentItem: Text {
                text: labelCombo.displayText.length
                      ? labelCombo.displayText
                      : "All labels"
                color: "#EEE"
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                leftPadding: 10
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

        // Score chips
        Row {
            spacing: 5
            Repeater {
                model: [
                    { t: "Any", v: 0 },
                    { t: "50%+", v: 0.5 },
                    { t: "70%+", v: 0.7 },
                    { t: "90%+", v: 0.9 }
                ]
                delegate: Rectangle {
                    width: scoreLabel.implicitWidth + 14
                    height: 24
                    radius: 12
                    color: Math.abs(root.filterMinScore - modelData.v) < 0.01 ? root.chipActive : root.chipIdle
                    border.color: Math.abs(root.filterMinScore - modelData.v) < 0.01 ? root.accent : root.softBorder
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

        // Time chips
        Row {
            spacing: 5
            Repeater {
                model: [
                    { t: "6h", v: 6 },
                    { t: "1 day", v: 24 },
                    { t: "3 days", v: 72 },
                    { t: "7 days", v: 168 }
                ]
                delegate: Rectangle {
                    width: timeLabel.implicitWidth + 14
                    height: 24
                    radius: 12
                    color: root.filterHours === modelData.v ? root.chipActive : root.chipIdle
                    border.color: root.filterHours === modelData.v ? root.accent : root.softBorder
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
            color: root.muted
            font.pixelSize: 11
        }

        ListView {
            id: list
            width: parent.width
            height: Math.max(50, col.height - 230)
            clip: true
            spacing: 8
            model: root.eventsModel

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: "#555"
                }
            }

            delegate: Rectangle {
                id: rowRect
                width: list.width
                height: 78
                radius: 10
                color: delArea.containsMouse ? root.cardHover : root.cardBg
                border.color: delArea.containsMouse ? "#4A4A58" : root.softBorder
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
                readonly property color accentCol: root.labelColor(evLabel)

                readonly property string thumbUrl: {
                    if (row && row.thumbnail) {
                        var t = "" + row.thumbnail
                        if (t.indexOf("data:") === 0 || t.indexOf("http") === 0)
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
                    return Qt.formatDateTime(new Date(sec * 1000), "MM/dd hh:mm:ss")
                }

                // Left accent bar by object type
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: 3
                    radius: 2
                    color: rowRect.accentCol
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 10

                    // Thumbnail
                    Rectangle {
                        width: 100
                        height: 56
                        radius: 6
                        color: "#121216"
                        border.color: "#333"
                        border.width: 1
                        clip: true

                        Image {
                            id: thumb
                            anchors.fill: parent
                            anchors.margins: 1
                            source: rowRect.thumbUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: thumb.status === Image.Loading
                            text: "…"
                            color: "#666"
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: thumb.status === Image.Error || (thumb.status === Image.Null && !rowRect.thumbUrl.length)
                            text: "No img"
                            color: "#555"
                            font.pixelSize: 10
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        width: Math.max(40, parent.width - 114)

                        Row {
                            spacing: 8
                            Text {
                                text: rowRect.evLabel
                                color: rowRect.accentCol
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Rectangle {
                                visible: rowRect.evScore > 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: scoreTxt.implicitWidth + 10
                                height: 16
                                radius: 8
                                color: "#1E1E28"
                                border.color: "#3A3A48"
                                Text {
                                    id: scoreTxt
                                    anchors.centerIn: parent
                                    text: Math.round(rowRect.evScore * 100) + "%"
                                    color: "#C8C8D0"
                                    font.pixelSize: 10
                                }
                            }
                        }

                        Text {
                            text: rowRect.evCamera
                            color: "#B0B0BA"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Text {
                            text: rowRect.formatTs(rowRect.evStart)
                            color: root.muted
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