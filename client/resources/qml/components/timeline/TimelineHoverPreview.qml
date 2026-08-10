import QtQuick 2.15

Item {
    id: hoverPreview
    width: bubble.width
    height: line.height + bubble.height + 4
    visible: false
    z: 100

    property string tsString: ""
    property string dateString: ""
    property real lineHeight: 40

    // Vertical cursor line (NX-style)
    Rectangle {
        id: line
        width: 2
        height: hoverPreview.lineHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        color: "#FFC107"
        opacity: 0.95
    }

    // Time bubble above the line
    Rectangle {
        id: bubble
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: line.top
        anchors.bottomMargin: 4
        width: Math.max(timeCol.implicitWidth + 20, 110)
        height: timeCol.implicitHeight + 12
        radius: 6
        color: "#E6000000"
        border.color: "#FFC107"
        border.width: 1

        Column {
            id: timeCol
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hoverPreview.dateString
                color: "#AAAAAA"
                font.pixelSize: 11
                visible: hoverPreview.dateString !== ""
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: hoverPreview.tsString
                color: "#FFC107"
                font.pixelSize: 16
                font.bold: true
            }
        }
    }
}