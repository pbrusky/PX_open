import QtQuick 2.15

Rectangle {
    id: hoverPreview
    width: 120
    height: 28
    radius: 4
    color: "#000000DD"
    border.color: "#888888"
    border.width: 1
    visible: false
    z: 100

    property string tsString: ""

    Text {
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: 11
        text: hoverPreview.tsString
    }
}
