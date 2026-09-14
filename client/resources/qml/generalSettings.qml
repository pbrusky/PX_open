import QtQuick 2.15
import QtQuick.Controls 2.15
import QtCore

Rectangle {
    id: root
    color: "#1e1e1e"
    anchors.fill: parent

    Settings {
        id: appSettings
        category: "general"
        property bool restoreLastFullscreen: false
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 24
        spacing: 20

        Row {
            width: parent.width
            spacing: 16

            Text {
                text: "General Settings"
                color: "#FFFFFF"
                font.pixelSize: 24
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: Math.max(0, parent.width - 280)
                height: 1
            }

            Button {
                id: backBtn
                text: "Back"
                width: 100
                height: 36
                anchors.verticalCenter: parent.verticalCenter

                background: Rectangle {
                    radius: 6
                    color: backBtn.down ? "#3A3A50" : (backBtn.hovered ? "#404060" : "#333333")
                    border.color: "#666666"
                    border.width: 1
                }
                contentItem: Text {
                    text: backBtn.text
                    color: "#FFFFFF"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    if (typeof mainWindow !== "undefined" && mainWindow
                            && typeof mainWindow.leaveSettings === "function") {
                        mainWindow.leaveSettings()
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: "#444444"
        }

        // Restore last fullscreen
        Row {
            spacing: 12
            width: parent.width

            Rectangle {
                width: 22
                height: 22
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: appSettings.restoreLastFullscreen ? "#3A6EA5" : "#333333"
                border.color: appSettings.restoreLastFullscreen ? "#5A9FD4" : "#777777"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.pixelSize: 14
                    font.bold: true
                    visible: appSettings.restoreLastFullscreen
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appSettings.restoreLastFullscreen = !appSettings.restoreLastFullscreen
                }
            }

            Text {
                text: "Open last view in fullscreen on startup (Kiosk Mode)"
                color: "#EEEEEE"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appSettings.restoreLastFullscreen = !appSettings.restoreLastFullscreen
                }
            }
        }

        Row {
            spacing: 12
            width: parent.width
            opacity: 0.55

            Rectangle {
                width: 22
                height: 22
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: "#333333"
                border.color: "#777777"
                border.width: 1
            }
            Text {
                text: "Enable dark mode (not implemented)"
                color: "#CCCCCC"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            spacing: 12
            width: parent.width
            opacity: 0.55

            Rectangle {
                width: 22
                height: 22
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: "#333333"
                border.color: "#777777"
                border.width: 1
            }
            Text {
                text: "Show notifications (not implemented)"
                color: "#CCCCCC"
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}