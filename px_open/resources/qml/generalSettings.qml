import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    color: "#1e1e1e"
    anchors.fill: parent

    Column {
        anchors.margins: 20
        spacing: 20

        Text {
            text: "General Settings"
            color: "white"
            font.pixelSize: 22
        }

        CheckBox {
            text: "Enable dark mode"
            checked: true
        }

        CheckBox {
            text: "Show notifications"
            checked: true
        }
    }
}
