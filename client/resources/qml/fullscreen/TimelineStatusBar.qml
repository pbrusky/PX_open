import QtQuick 2.15

Rectangle {
    id: root
    height: 32
    color: "#161616"

    property var timeline: null
    property bool calendarOpen: false

    signal calendarToggled()
    signal zoomOut()
    signal zoomIn()
    signal resetZoom()

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: {
            if (!timeline)
                return ""
            if (timeline.hoverTsMs > 0)
                return "Cursor   " + timeline.formatFull(timeline.hoverTsMs)
            if (timeline.isPlayback && timeline.playbackPositionMs > 0)
                return "Playback   " + timeline.formatFull(timeline.playbackPositionMs)
            return "Live   " + timeline.formatFull(timeline.currentTimeMs)
        }
        color: {
            if (!timeline)
                return "#00C853"
            if (timeline.hoverTsMs > 0)
                return "#FFC107"
            return timeline.isPlayback ? "#FFC107" : "#00C853"
        }
        font.pixelSize: 16
        font.bold: true
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
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

        // Calendar button — emoji icon (no "Cal" text)
        Rectangle {
            width: 30
            height: 22
            radius: 3
            color: root.calendarOpen ? "#555" : "#333"
            border.color: root.calendarOpen ? "#FFC107" : "#666"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "📅"
                font.pixelSize: 14
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