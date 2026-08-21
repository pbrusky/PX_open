import QtQuick 2.15

Rectangle {
    id: root
    width: 280
    height: 310
    color: "#1E1E1E"
    border.color: "#555"
    border.width: 1
    radius: 6
    visible: false

    property var timeline: null
    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth() + 1

    signal daySelected(int year, int month, int day)

    function calMonthName() {
        var names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        return names[calMonth - 1] + " " + calYear
    }

    function calCellDay(index) {
        var first = new Date(calYear, calMonth - 1, 1)
        var startPad = (first.getDay() + 6) % 7
        var dayNum = index - startPad + 1
        var dim = new Date(calYear, calMonth, 0).getDate()
        if (dayNum < 1 || dayNum > dim)
            return 0
        return dayNum
    }

    function dayHasRecording(y, m, d) {
        if (!timeline)
            return false
        return timeline.dayHasRecording(y, m, d)
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Row {
            width: parent.width
            spacing: 8
            Rectangle {
                width: 28
                height: 28
                radius: 4
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: "white"
                    font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        calMonth -= 1
                        if (calMonth < 1) {
                            calMonth = 12
                            calYear -= 1
                        }
                    }
                }
            }
            Text {
                width: parent.width - 100
                height: 28
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: calMonthName()
                color: "white"
                font.pixelSize: 14
                font.bold: true
            }
            Rectangle {
                width: 28
                height: 28
                radius: 4
                color: "#333"
                Text {
                    anchors.centerIn: parent
                    text: ">"
                    color: "white"
                    font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        calMonth += 1
                        if (calMonth > 12) {
                            calMonth = 1
                            calYear += 1
                        }
                    }
                }
            }
            Rectangle {
                width: 28
                height: 28
                radius: 4
                color: "#444"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: "#FFCDD2"
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.visible = false
                }
            }
        }

        Row {
            width: parent.width
            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                Text {
                    width: parent.width / 7
                    height: 20
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: "#888"
                    font.pixelSize: 11
                }
            }
        }

        Grid {
            id: dayGrid
            width: parent.width
            columns: 7
            spacing: 2
            Repeater {
                model: 42
                Rectangle {
                    property int dayNum: calCellDay(index)
                    property bool hasRec: dayNum > 0 && dayHasRecording(calYear, calMonth, dayNum)
                    property bool isToday: {
                        var n = new Date()
                        return dayNum > 0
                            && calYear === n.getFullYear()
                            && calMonth === (n.getMonth() + 1)
                            && dayNum === n.getDate()
                    }
                    width: (dayGrid.width - 12) / 7
                    height: 32
                    radius: 4
                    color: dayNum <= 0 ? "transparent" : (hasRec ? "#1B5E20" : "#2A2A2A")
                    border.color: isToday ? "#FFC107" : "transparent"
                    border.width: isToday ? 1 : 0
                    Text {
                        anchors.centerIn: parent
                        text: dayNum > 0 ? dayNum : ""
                        color: hasRec ? "#A5D6A7" : (dayNum > 0 ? "#CCC" : "transparent")
                        font.pixelSize: 12
                        font.bold: hasRec
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: dayNum > 0
                        onClicked: root.daySelected(calYear, calMonth, dayNum)
                    }
                }
            }
        }

        Text {
            width: parent.width
            text: "Green = has recording. Click a day to jump. Esc or outside closes."
            color: "#777"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}