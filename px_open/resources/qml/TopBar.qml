import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: topbarWrapper
    width: parent.width

    height: collapsed ? 0 : 48
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

    QtObject {
        id: state
        property bool isStartupPage: false
        property bool isCameraPage: false
    }

    property alias isStartupPage: state.isStartupPage
    property alias isCameraPage: state.isCameraPage
    property alias serverName: serverNameText.text

    // expose maximize state to MainWindow
    QtObject {
        id: maximizeState
        property bool isMaximized: false
    }
    property alias isMaximized: maximizeState.isMaximized

    signal disconnectRequested()
    signal exitRequested()
    signal minimizeRequested()
    signal restoreRequested()
    signal maximizeRequested()

    Rectangle {
        anchors.fill: parent
        color: "#1E1E1E"
    }

    Rectangle {
        id: menuButton
        width: 36
        height: 36
        radius: 4
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: hovered ? "#2A2A2A" : "#1E1E1E"
        property bool hovered: false

        Column {
            anchors.centerIn: parent
            spacing: 3
            Rectangle { width: 20; height: 2; color: "white"; radius: 1 }
            Rectangle { width: 20; height: 2; color: "white"; radius: 1 }
            Rectangle { width: 20; height: 2; color: "white"; radius: 1 }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: menuButton.hovered = true
            onExited: menuButton.hovered = false
            onClicked: menuPopup.open()
        }
    }

    Popup {
        id: menuPopup
        modal: false
        focus: true
        x: menuButton.x
        y: menuButton.y + menuButton.height + 4
        width: 180

        background: Rectangle {
            color: "#2A2A2A"
            radius: 6
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            Rectangle {
                width: parent.width
                height: 40
                radius: 4
                color: hovered ? "#454545" : "#2A2A2A"
                property bool hovered: false

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Disconnect"
                    color: "#E0E0E0"
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                    onClicked: {
                        menuPopup.close()
                        topbarWrapper.disconnectRequested()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#555555"
            }

            Rectangle {
                width: parent.width
                height: 40
                radius: 4
                color: hovered ? "#454545" : "#2A2A2A"
                property bool hovered: false

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Exit"
                    color: "#E0E0E0"
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                    onClicked: {
                        menuPopup.close()
                        topbarWrapper.exitRequested()
                    }
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Text {
            id: serverNameText
            text: "Frigate System"
            color: "white"
            font.pixelSize: 18
        }

        Image {
            source: "qrc:/app/assets/icons/user.svg"
            width: 24
            height: 24
        }

        Rectangle {
            id: minimizeButton
            width: 28
            height: 28
            radius: 4
            color: hovered ? "#3A3A3A" : "#2A2A2A"
            property bool hovered: false

            Text {
                anchors.centerIn: parent
                text: "—"
                color: "white"
                font.pixelSize: 20
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: minimizeButton.hovered = true
                onExited: minimizeButton.hovered = false
                onClicked: topbarWrapper.minimizeRequested()
            }
        }

        Rectangle {
            id: maximizeRestoreButton
            width: 28
            height: 28
            radius: 4
            color: hovered ? "#3A3A3A" : "#2A2A2A"
            property bool hovered: false

            Text {
                anchors.centerIn: parent
                text: maximizeState.isMaximized ? "▢" : "⬜"
                color: "white"
                font.pixelSize: 16
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: maximizeRestoreButton.hovered = true
                onExited: maximizeRestoreButton.hovered = false

                onClicked: {
                    if (maximizeState.isMaximized) {
                        topbarWrapper.restoreRequested()
                    } else {
                        topbarWrapper.maximizeRequested()
                    }
                }
            }
        }

        Rectangle {
            id: exitButton
            width: 28
            height: 28
            radius: 4
            color: hovered ? "#3A3A3A" : "#2A2A2A"
            property bool hovered: false

            Text {
                anchors.centerIn: parent
                text: "X"
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: exitButton.hovered = true
                onExited: exitButton.hovered = false
                onClicked: topbarWrapper.exitRequested()
            }
        }
    }
}
