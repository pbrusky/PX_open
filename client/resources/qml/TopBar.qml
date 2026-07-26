import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: topbarWrapper
    objectName: "TopBar"

    width: parent.width
    height: collapsed ? 0 : 48
    Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

    property bool isStartupPage: false
    property bool isCameraPage: false
    property string serverName: ""
    property bool isMaximized: false

    signal disconnectRequested()
    signal exitRequested()
    signal minimizeRequested()
    signal restoreRequested()
    signal maximizeRequested()
    signal addCameraRequested()
    signal aboutRequested()

    //
    // Right‑click menu on server name
    //
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

    //
    // Double‑click topbar to toggle fullscreen
    //
    MouseArea {
        id: topbarDoubleClickArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        propagateComposedEvents: true

        onDoubleClicked: {
            if (mainWindow.isFullscreen) {
                mainWindow.exitTrueFullscreen()
                topbarWrapper.isMaximized = false
            } else {
                mainWindow.enterTrueFullscreen()
                topbarWrapper.isMaximized = true
            }
        }

        onPressed: mainWindow.startSystemMove()
    }

    //
    // Hamburger menu button
    //
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

    //
    // Main menu popup
    //
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
            text: "About"
            onTriggered: topbarWrapper.aboutRequested()
        }

        MenuItem {
            text: "Exit"
            onTriggered: topbarWrapper.exitRequested()
        }
    }

    //
    // Right‑side window controls
    //
    Row {
        id: buttonRow
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        //
        // Server name
        //
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

        //
        // Minimize
        //
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

        //
        // Maximize / Restore
        //
        Rectangle {
            id: maximizeRestoreButton
            width: 28
            height: 28
            radius: 4
            color: hovered ? "#3A3A3A" : "#2A2A2A"
            property bool hovered: false

            Text {
                anchors.centerIn: parent
                text: topbarWrapper.isMaximized ? "▢" : "⬜"
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
                    if (topbarWrapper.isMaximized) {
                        mainWindow.exitTrueFullscreen()
                        topbarWrapper.isMaximized = false
                    } else {
                        mainWindow.enterTrueFullscreen()
                        topbarWrapper.isMaximized = true
                    }
                }
            }
        }

        //
        // Exit
        //
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
