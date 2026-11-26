import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 440
    height: 300
    padding: 0

    property string cameraLabel: ""
    property real startMs: 0
    property real endMs: 0

    signal confirmed(real startMs, real endMs)
    signal cancelled()

    function pad2(n) {
        n = Math.floor(Number(n) || 0)
        return (n < 10 ? "0" : "") + n
    }

    function fillFromMs(ms) {
        var d = new Date(ms)
        return {
            date: d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()),
            time: pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
        }
    }

    function parseDateTime(dateStr, timeStr) {
        var dp = String(dateStr || "").trim().split("-")
        var tp = String(timeStr || "").trim().split(":")
        if (dp.length < 3 || tp.length < 2)
            return -1
        var y = parseInt(dp[0], 10)
        var m = parseInt(dp[1], 10)
        var day = parseInt(dp[2], 10)
        var hh = parseInt(tp[0], 10)
        var mm = parseInt(tp[1], 10)
        var ss = tp.length > 2 ? parseInt(tp[2], 10) : 0
        if (isNaN(y) || isNaN(m) || isNaN(day) || isNaN(hh) || isNaN(mm) || isNaN(ss))
            return -1
        var dt = new Date(y, m - 1, day, hh, mm, ss)
        var t = dt.getTime()
        return isNaN(t) ? -1 : t
    }

    function openWith(cam, sMs, eMs) {
        cameraLabel = cam || ""
        startMs = sMs
        endMs = eMs
        var a = fillFromMs(sMs)
        var b = fillFromMs(eMs)
        startDateField.text = a.date
        startTimeField.text = a.time
        endDateField.text = b.date
        endTimeField.text = b.time
        errorText.text = ""
        open()
    }

    function durationLabel() {
        var s = parseDateTime(startDateField.text, startTimeField.text)
        var e = parseDateTime(endDateField.text, endTimeField.text)
        if (s < 0 || e < 0 || e <= s)
            return "—"
        var sec = (e - s) / 1000
        if (sec < 90)
            return Math.round(sec) + " sec"
        if (sec < 3600)
            return Math.round(sec / 60) + " min"
        return (sec / 3600).toFixed(1) + " hours"
    }

    function tryConfirm() {
        var s = parseDateTime(startDateField.text, startTimeField.text)
        var e = parseDateTime(endDateField.text, endTimeField.text)
        if (s < 0 || e < 0) {
            errorText.text = "Use dates like 2026-09-21 and times like 14:30:00"
            return
        }
        if (e <= s) {
            errorText.text = "End must be after start"
            return
        }
        if ((e - s) < 2000) {
            errorText.text = "Range must be at least 2 seconds"
            return
        }
        errorText.text = ""
        close()
        confirmed(s, e)
    }

    background: Rectangle {
        color: "#1E1E24"
        border.color: "#6A8AFF"
        border.width: 1
        radius: 8
    }

    contentItem: ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        Text {
            text: "Export footage"
            color: "white"
            font.pixelSize: 20
            font.bold: true
            Layout.fillWidth: true
        }

        Text {
            text: root.cameraLabel !== "" ? ("Camera:  " + root.cameraLabel) : ""
            color: "#BBBBBB"
            font.pixelSize: 15
            visible: root.cameraLabel !== ""
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "Start"
                color: "#DDDDDD"
                font.pixelSize: 15
                Layout.preferredWidth: 52
            }
            TextField {
                id: startDateField
                Layout.preferredWidth: 130
                font.pixelSize: 15
                placeholderText: "YYYY-MM-DD"
                color: "white"
                selectByMouse: true
                background: Rectangle {
                    color: "#2A2A32"
                    radius: 4
                    border.color: "#555"
                    implicitHeight: 34
                }
            }
            TextField {
                id: startTimeField
                Layout.preferredWidth: 110
                font.pixelSize: 15
                placeholderText: "HH:MM:SS"
                color: "white"
                selectByMouse: true
                background: Rectangle {
                    color: "#2A2A32"
                    radius: 4
                    border.color: "#555"
                    implicitHeight: 34
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: "End"
                color: "#DDDDDD"
                font.pixelSize: 15
                Layout.preferredWidth: 52
            }
            TextField {
                id: endDateField
                Layout.preferredWidth: 130
                font.pixelSize: 15
                placeholderText: "YYYY-MM-DD"
                color: "white"
                selectByMouse: true
                background: Rectangle {
                    color: "#2A2A32"
                    radius: 4
                    border.color: "#555"
                    implicitHeight: 34
                }
            }
            TextField {
                id: endTimeField
                Layout.preferredWidth: 110
                font.pixelSize: 15
                placeholderText: "HH:MM:SS"
                color: "white"
                selectByMouse: true
                background: Rectangle {
                    color: "#2A2A32"
                    radius: 4
                    border.color: "#555"
                    implicitHeight: 34
                }
            }
        }

        Text {
            text: "Duration:  " + root.durationLabel()
            color: "#8B9BFF"
            font.pixelSize: 15
            Layout.fillWidth: true
        }

        Text {
            id: errorText
            color: "#FF6B6B"
            font.pixelSize: 14
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                font.pixelSize: 15
                onClicked: {
                    root.close()
                    root.cancelled()
                }
            }

            Button {
                text: "Save"
                font.pixelSize: 15
                highlighted: true
                onClicked: root.tryConfirm()
            }
        }
    }
}