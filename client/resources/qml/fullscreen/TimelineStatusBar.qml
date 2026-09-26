import QtQuick 2.15

Rectangle {
    id: root
    height: 32
    color: "#161616"

    property var timeline: null
    property bool calendarOpen: false
    property bool exportBusy: false
    // -1 = unknown size (indeterminate); 0..100 when known / done
    property real exportPercent: 0

    signal calendarToggled()
    signal zoomOut()
    signal zoomIn()
    signal resetZoom()
    signal exportRequested()
    signal clearExportRange()
    signal cancelExportRequested()

    readonly property bool hasExportRange: timeline
        && timeline.exportStartMs > 0
        && timeline.exportEndMs > timeline.exportStartMs

    readonly property string cameraLabel: {
        if (!timeline)
            return ""
        var n = timeline.cameraName || timeline.cameraId || ""
        return ("" + n).length ? ("" + n) : ""
    }

    Text {
        id: camLabel
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: root.cameraLabel.length > 0
        text: root.cameraLabel
        color: "#E8E8F0"
        font.pixelSize: 13
        font.bold: true
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width * 0.22)
    }

    Rectangle {
        id: camSep
        anchors.left: camLabel.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: 14
        color: "#444"
        visible: camLabel.visible
    }

    Text {
        id: leftLabel
        anchors.left: camLabel.visible ? camSep.right : parent.left
        anchors.leftMargin: camLabel.visible ? 10 : 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.40)
        elide: Text.ElideRight
        text: {
            if (!timeline)
                return ""
            if (root.exportBusy) {
                var extra = (timeline.exportStatusMessage && timeline.exportStatusMessage.length)
                            ? ("  " + timeline.exportStatusMessage)
                            : ""
                if (root.exportPercent >= 100)
                    return "Saved" + extra
                if (root.exportPercent < 0)
                    return "Downloading…" + extra
                return "Downloading…  " + Math.round(root.exportPercent) + "%" + extra
            }
            if (root.hasExportRange) {
                return "Export  "
                     + timeline.formatFull(timeline.exportStartMs)
                     + "  →  "
                     + Qt.formatDateTime(new Date(timeline.exportEndMs), "hh:mm:ss")
                     + "  (" + timeline.exportSpanLabel() + ")"
            }
            if (timeline.hoverTsMs > 0)
                return "Cursor   " + timeline.formatFull(timeline.hoverTsMs)
            if (timeline.isPlayback && timeline.playbackPositionMs > 0)
                return "Playback   " + timeline.formatFull(timeline.playbackPositionMs)
            return "Live   " + timeline.formatFull(timeline.currentTimeMs)
        }
        color: {
            if (!timeline)
                return "#00C853"
            if (root.exportBusy || root.hasExportRange)
                return "#6A8AFF"
            if (timeline.hoverTsMs > 0)
                return "#FFC107"
            return timeline.isPlayback ? "#FFC107" : "#00C853"
        }
        font.pixelSize: 14
        font.bold: true
    }

    Rectangle {
        id: progressTrack
        visible: root.exportBusy
        anchors.left: leftLabel.right
        anchors.leftMargin: 12
        anchors.right: rightRow.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 10
        radius: 4
        color: "#2A2A32"
        border.color: "#444"
        border.width: 1
        clip: true

        Rectangle {
            visible: root.exportPercent >= 0
            width: parent.width * Math.max(0, Math.min(1, root.exportPercent / 100.0))
            height: parent.height
            radius: 4
            color: root.exportPercent >= 100 ? "#00C853" : "#6A8AFF"
        }

        Rectangle {
            id: indeterminateChunk
            visible: root.exportPercent < 0
            width: Math.max(24, parent.width * 0.28)
            height: parent.height
            radius: 4
            color: "#6A8AFF"

            SequentialAnimation on x {
                running: indeterminateChunk.visible && root.exportBusy
                loops: Animation.Infinite
                NumberAnimation {
                    from: -indeterminateChunk.width
                    to: progressTrack.width
                    duration: 1200
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        // Cancel active download
        Rectangle {
            width: 64
            height: 22
            radius: 3
            visible: root.exportBusy && root.exportPercent < 100
            color: "#5A2020"
            border.color: "#E57373"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "Cancel"
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelExportRequested()
            }
        }

        Rectangle {
            width: 64
            height: 22
            radius: 3
            visible: root.hasExportRange && !root.exportBusy
            color: "#2F4A8A"
            border.color: "#6A8AFF"
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "Export"
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.exportRequested()
            }
        }

        Rectangle {
            width: 28
            height: 22
            radius: 3
            visible: root.hasExportRange && !root.exportBusy
            color: "#333"
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: "#ccc"
                font.pixelSize: 12
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearExportRange()
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.hasExportRange && !root.exportBusy
            text: {
                if (!timeline)
                    return ""
                var s = timeline.effectiveStartTs()
                var e = timeline.effectiveEndTs()
                return Qt.formatDateTime(new Date(s * 1000), "hh:mm:ss")
                       + "  -  "
                       + Qt.formatDateTime(new Date(e * 1000), "hh:mm:ss")
                       + "  (" + timeline.viewSpanLabel() + ")"
            }
            color: "#888888"
            font.pixelSize: 12
        }

        Rectangle {
            width: 30
            height: 22
            radius: 3
            color: root.calendarOpen ? "#555" : "#333"
            border.color: root.calendarOpen ? "#FFC107" : "#666"
            border.width: 1
            Image {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "qrc:/app/assets/icons/nx/calendar.svg"
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.calendarToggled()
            }
        }

        Rectangle {
            width: 28
            height: 22
            radius: 3
            color: "#333"
            Text {
                anchors.centerIn: parent
                text: "−"
                color: "white"
                font.pixelSize: 16
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.zoomOut()
            }
        }
        Rectangle {
            width: 28
            height: 22
            radius: 3
            color: "#333"
            Text {
                anchors.centerIn: parent
                text: "+"
                color: "white"
                font.pixelSize: 16
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.zoomIn()
            }
        }
        Rectangle {
            width: 44
            height: 22
            radius: 3
            color: "#333"
            Text {
                anchors.centerIn: parent
                text: "1:1"
                color: "white"
                font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.resetZoom()
            }
        }
    }
}