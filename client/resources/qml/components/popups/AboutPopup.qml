import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PxOpen 1.0

Item {
    id: aboutPopup
    objectName: "AboutPopup"

    property var mainWindow
    signal closeRequested()

    // Label vs value colors
    readonly property color labelColor: "#AAAAAA"
    readonly property color valueColor: "#FFFFFF"
    readonly property color mutedColor: "#888888"

    anchors.fill: parent
    z: 999999

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: Math.min(560, mainWindow ? mainWindow.width - 40 : 560)
        height: Math.max(500, contentCol.implicitHeight + 90)
        radius: 12
        color: "#111111"
        border.color: "#333333"
        border.width: 1
        clip: true

        x: mainWindow ? (mainWindow.width - width) / 2 : 0
        y: mainWindow ? Math.max(10, (mainWindow.height - height) / 2) : 0

        // Reusable label + value row
        component InfoRow: Row {
            property string label: ""
            property string value: ""
            property color valueTextColor: aboutPopup.valueColor
            width: parent ? parent.width : 400
            spacing: 6

            Text {
                text: label
                color: aboutPopup.labelColor
                font.pixelSize: 16
            }
            Text {
                width: parent.width - parent.children[0].width - parent.spacing
                text: value
                color: valueTextColor
                font.pixelSize: 16
                wrapMode: Text.WordWrap
            }
        }

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 28
            anchors.bottomMargin: 70
            spacing: 12

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "qrc:/app/assets/icon.png"
                width: 72
                height: 72
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                width: parent.width
                text: "About PX Open"
                color: "white"
                font.pixelSize: 26
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#333"
            }

            InfoRow {
                label: "OS:"
                value: AboutInfo.osName
            }

            InfoRow {
                label: "CPU:"
                value: AboutInfo.cpuLoading ? "Loading..." : AboutInfo.cpuName
                valueTextColor: AboutInfo.cpuLoading ? aboutPopup.mutedColor : aboutPopup.valueColor
            }

            InfoRow {
                label: "Memory:"
                value: AboutInfo.memoryLoading ? "Loading..." : AboutInfo.memoryInfo
                valueTextColor: AboutInfo.memoryLoading ? aboutPopup.mutedColor : aboutPopup.valueColor
            }

            Column {
                width: parent.width
                spacing: 4

                Text {
                    width: parent.width
                    text: "GPUs:"
                    color: aboutPopup.labelColor
                    font.pixelSize: 16
                }

                Text {
                    width: parent.width
                    visible: AboutInfo.gpusLoading
                    text: "Loading..."
                    color: aboutPopup.mutedColor
                    font.pixelSize: 16
                }

                Repeater {
                    model: AboutInfo.gpusLoading ? [] : AboutInfo.gpuList

                    Text {
                        width: parent.width
                        text: "• " + modelData
                        color: aboutPopup.valueColor
                        font.pixelSize: 16
                        wrapMode: Text.WrapAnywhere
                    }
                }

                Text {
                    width: parent.width
                    visible: !AboutInfo.gpusLoading && AboutInfo.gpuList.length === 0
                    text: "• Unknown"
                    color: aboutPopup.valueColor
                    font.pixelSize: 16
                }
            }

            InfoRow {
                label: "Graphics API:"
                value: AboutInfo.graphicsApi
            }

            InfoRow {
                label: "Hardware Decoding:"
                value: AboutInfo.hardwareDecoding ? "Enabled" : "Disabled"
                valueTextColor: AboutInfo.hardwareDecoding ? "#81C784" : "#FF8A80"
            }

            InfoRow {
                label: "Qt:"
                value: AboutInfo.qtVersion
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#333"
            }

            Text {
                width: parent.width
                text: "PX Open Client"
                color: "#BBBBBB"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
            }

            InfoRow {
                label: "Version:"
                value: "" + PX_VERSION
                valueTextColor: "#90CAF9"
            }

            Text {
                width: parent.width
                text: "Frigate Integration"
                color: "#BBBBBB"
                font.pixelSize: 16
                wrapMode: Text.WordWrap
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
                implicitWidth: 100
                implicitHeight: 36
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