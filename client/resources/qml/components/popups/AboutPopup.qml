import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PxOpen 1.0

Item {
    id: aboutPopup
    objectName: "AboutPopup"

    property var mainWindow
    signal closeRequested()

    anchors.fill: parent
    z: 999999

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: 480
        height: 420
        radius: 12
        color: "#111111"
        border.color: "#333333"
        border.width: 1

        x: mainWindow ? (mainWindow.width - width) / 2 : 0
        y: mainWindow ? (mainWindow.height - height) / 2 : 0

        Column {
            anchors.centerIn: parent
            spacing: 14

            Text {
                text: "About PX Open"
                color: "white"
                font.pixelSize: 26
                font.bold: true
            }

            Rectangle { width: 360; height: 1; color: "#333" }

            // Multi-GPU list
            Text {
                text: AboutInfo.gpuList.length > 0
                      ? "GPUs: " + AboutInfo.gpuList.join(", ")
                      : "GPUs: Loading..."
                color: "white"
                font.pixelSize: 18
            }

            // Vendor list
            Text {
                text: AboutInfo.gpuVendors.length > 0
                      ? "Vendors: " + AboutInfo.gpuVendors.join(", ")
                      : "Vendors: Loading..."
                color: "white"
                font.pixelSize: 18
            }

            Text {
                text: "Graphics API: " + AboutInfo.graphicsApi
                color: "white"
                font.pixelSize: 18
            }

            Text {
                text: "Hardware Decoding: " +
                      (AboutInfo.hardwareDecoding ? "Enabled" : "Disabled")
                color: AboutInfo.hardwareDecoding ? "lightgreen" : "red"
                font.pixelSize: 18
            }

            Rectangle { width: 360; height: 1; color: "#333" }

            Text {
                text: "PX Open Client"
                color: "#BBBBBB"
                font.pixelSize: 16
            }

            Text {
                text: "Frigate Integration"
                color: "#BBBBBB"
                font.pixelSize: 16
            }
        }

        Button {
            id: closeButton
            text: "Close"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20

            background: Rectangle {
                color: "#333333"
                radius: 6
            }

            contentItem: Text {
                text: closeButton.text
                color: "white"
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: aboutPopup.closeRequested()
        }
    }
}
