import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: timeline
    height: 60
    width: parent.width
    color: "#000000AA"

    property var events: []
    property var recordings: []
    property real position: 0

    Row {
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: events.length

            Rectangle {
                width: 4
                height: parent.height
                color: "red"
            }
        }
    }
}
