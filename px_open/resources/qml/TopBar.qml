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
    signal addCameraRequested()

    Menu {
        id: serverNameContextMenu
        x: serverNameContainer.x
        y: serverNameContainer.height

        MenuItem {
            text: "Add Camera"
            onTriggered: topbarWrapper.addCameraRequested()
        }

        MenuItem {
            text: "Disconnect"
            onTriggered: topbarWrapper.disconnectRequested()
        }
    }

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

    Menu {
        id: menuPopup
        x: menuButton.x
        y: menuButton.y + menuButton.height + 4

        MenuItem {
            text: "Disconnect"
            onTriggered: topbarWrapper.disconnectRequested()
        }

        MenuSeparator {}

        MenuItem {
            text: "Exit"
            onTriggered: topbarWrapper.exitRequested()
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

            Rectangle {
                id: serverNameContainer
                width: serverNameText.paintedWidth + 24
                height: parent.height
                color: "transparent"

                Text {
                    id: serverNameText
                    anchors.centerIn: parent
                    text: topbarWrapper.serverName !== "" ? topbarWrapper.serverName : "Frigate System"
                    color: "white"
                    font.pixelSize: 18
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.RightButton | Qt.LeftButton
                    preventStealing: true

                    onPressed: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            serverNameContextMenu.open()
                        }
                    }
                }
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
