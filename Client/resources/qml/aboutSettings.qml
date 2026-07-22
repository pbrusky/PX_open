import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    color: "#1e1e1e"
    anchors.fill: parent

    Column {
        anchors.margins: 20
        spacing: 20

        Text {
            text: "About PX Client"
            color: "white"
            font.pixelSize: 22
        }

        Text {
            text: "Version 0.1.0"
            color: "#bbbbbb"
        }

        Text {
            text: "Built with Qt 6.5.3"
            color: "#bbbbbb"
        }

        Text {
            text: "Backend: Frigate"
            color: "#bbbbbb"
        }
    }
}
