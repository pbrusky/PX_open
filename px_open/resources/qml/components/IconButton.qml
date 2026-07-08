import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    width: 32
    height: 32

    property alias icon: iconImage.source
    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: "transparent"
    }

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: 24
        height: 24
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
