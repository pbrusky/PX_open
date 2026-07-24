import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    color: "#1e1e1e"
    anchors.fill: parent

    // ⭐ REQUIRED so MainWindow can inject the sidebar
    property var sidebar

    Column {
        anchors.margins: 20
        spacing: 20

        Text {
            text: "Server Settings"
            color: "white"
            font.pixelSize: 22
        }

        TextField {
            placeholderText: "Server Address"
            width: 300
        }

        Button {
            text: "Reconnect"
            width: 150
        }
    }
}
