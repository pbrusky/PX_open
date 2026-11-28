import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PxOpen 1.0
import "qrc:/app/resources/qml/components"

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
    signal settingsRequested()

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
        color: NxStyle.panel
        border.color: NxStyle.border
        border.width: 1
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
        radius: NxStyle.radius
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: hovered ? NxStyle.hover : NxStyle.panel
        property bool hovered: false

        Column {
            anchors.centerIn: parent
            spacing: 3
            Rectangle { width: 20; height: 2; color: NxStyle.text; radius: 1 }
            Rectangle { width: 20; height: 2; color: NxStyle.text; radius: 1 }
            Rectangle { width: 20; height: 2; color: NxStyle.text; radius: 1 }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            preventStealing: true
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
            text: "Settings"
            onTriggered: topbarWrapper.settingsRequested()
        }

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
        spacing: 8

        //
        // Server name
        //
        Rectangle {
            id: serverNameContainer
            width: Math.min(serverNameText.implicitWidth + 24, parent.width * 0.5)
            height: parent.height
            color: "transparent"

            Text {
                id: serverNameText
                anchors.centerIn: parent
                text: topbarWrapper.serverName !== "" ? topbarWrapper.serverName : "Frigate System"
                color: NxStyle.text
                font.pixelSize: 16
                elide: Text.ElideRight
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
            radius: 1
            color: hovered ? NxStyle.hover : NxStyle.panelAlt
            property bool hovered: false

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: "qrc:/app/assets/icons/nx/minimize.svg"
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: minimizeMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true

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
            radius: 1
            color: hovered ? NxStyle.hover : NxStyle.panelAlt
            property bool hovered: false

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: topbarWrapper.isMaximized
                        ? "qrc:/app/assets/icons/nx/restore.svg"
                        : "qrc:/app/assets/icons/nx/maximize.svg"
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true

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
            radius: 1
            color: hovered ? "#5A1A1A" : NxStyle.panelAlt
            property bool hovered: false

            Image {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: "qrc:/app/assets/icons/nx/close.svg"
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true

                onEntered: exitButton.hovered = true
                onExited: exitButton.hovered = false
                onClicked: topbarWrapper.exitRequested()
            }
        }
    }
}