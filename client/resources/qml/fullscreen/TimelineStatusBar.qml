import QtQuick 2.15

Rectangle {
    id: root
    height: 32
    color: "#161616"

    property var timeline: null
    property bool calendarOpen: false
    property bool exportBusy: false
    property real exportPercent: 0   // 0..100 during transfer; StatusBar only shown when exportBusy

    signal calendarToggled()
    signal zoomOut()
    signal zoomIn()
    signal resetZoom()
    signal exportRequested()
    signal clearExportRange()

    readonly property bool hasExportRange: timeline
        && timeline.exportStartMs > 0
        && timeline.exportEndMs > timeline.exportStartMs

    Text {
        id: leftLabel
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.42)
        elide: Text.ElideRight
        text: {
            if (!timeline)
                return ""
            if (root.exportBusy) {
                var pct = Math.round(root.exportPercent)
                var extra = (timeline.exportStatusMessage && timeline.exportStatusMessage.length)
                            ? ("  ·  " + timeline.exportStatusMessage)
                            : ""
                if (pct >= 100)
                    return "Saved" + extra
                return "Downloading…  " + pct + "%" + extra
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
        // Only while download is active — hides when FullscreenTimeline sets exportBusy = false
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
            width: parent.width * Math.max(0, Math.min(1, root.exportPercent / 100.0))
            height: parent.height
            radius: 4
            color: root.exportPercent >= 100 ? "#00C853" : "#6A8AFF"
        }
    }

    Row {
        id: rightRow
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

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