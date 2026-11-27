import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PxOpen 1.0
import "qrc:/app/resources/qml/components"

Item {
    id: sidebar
    objectName: "Sidebar"

    property var frigateRef

    visible: isCameraPage
    width: isCameraPage ? (collapsed ? 0 : 260) : 0
    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    height: parent ? parent.height : 900

    property bool isStartupPage: false
    property bool isCameraPage: false
    property bool collapsed: false

    signal cameraSelected(string cameraId)
    signal cameraFullscreenRequested(string cameraName)
    signal requestRemoveCamera(string cameraId)
    signal navigate(string page)
    signal cameraDropped(real x, real y, string cameraName)

    property var cameraList: []
    property string selectedCameraId: ""
    property string serverName: ""

    // [{ name: "…", cameras: [...] }, ...] — filled from ServerView
    property var layoutList: []
    property string selectedLayoutName: ""

    readonly property var palette: NxStyle

    Rectangle {
        anchors.fill: parent
        color: palette.background
    }

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // Server title
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Menu {
                id: serverNameContextMenu
                x: serverNameContainer.x
                y: serverNameContainer.height
                MenuItem {
                    text: "Add Camera"
                    onTriggered: sidebar.navigate("addCamera")
                }
                MenuItem {
                    text: "Edit Frigate Config"
                    onTriggered: sidebar.navigate("editFrigateConfig")
                }
                MenuItem {
                    text: "Edit go2rtc Config"
                    onTriggered: sidebar.navigate("editGo2rtcConfig")
                }
                MenuItem {
                    text: "Disconnect"
                    onTriggered: sidebar.navigate("disconnect")
                }
            }

            Rectangle {
                id: serverNameContainer
                anchors.fill: parent
                color: "transparent"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: serverName !== "" ? serverName : "No server"
                    color: palette.text
                    font.pixelSize: 16
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onPressed: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            serverNameContextMenu.open()
                    }
                }
            }
        }

        // Camera tree with favorites, groups, and search
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1

            CameraTree {
                id: cameraTree
                anchors.fill: parent
                frigateRef: sidebar.frigateRef
                cameraList: sidebar.cameraList
                serverKey: (sidebar.frigateRef
                            && sidebar.frigateRef.serverIp
                            && ("" + sidebar.frigateRef.serverIp).length)
                           ? ("" + sidebar.frigateRef.serverIp)
                           : sidebar.serverName
                selectedCameraId: sidebar.selectedCameraId

                onCameraSelected: function(cameraId) {
                    sidebar.selectedCameraId = cameraId
                    sidebar.cameraSelected(cameraId)
                }
                onCameraFullscreenRequested: function(cameraName) {
                    sidebar.cameraFullscreenRequested(cameraName)
                }
                onRequestRemoveCamera: function(cameraId) {
                    sidebar.requestRemoveCamera(cameraId)
                }
                onNavigate: function(page) { sidebar.navigate(page) }
                onCameraDropped: function(x, y, cameraName) {
                    sidebar.cameraDropped(x, y, cameraName)
                }
            }
        }

        // Layouts header
        Text {
            Layout.fillWidth: true
            text: "Layouts"
            color: palette.textMuted
            font.pixelSize: 11
            font.bold: true
        }

        // Layout list (or empty state)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 0.65   // slightly less stretch than cameras

            ListView {
                id: layoutListView
                anchors.fill: parent
                clip: true
                visible: sidebar.layoutList.length > 0
                model: sidebar.layoutList

                delegate: Rectangle {
                    id: layoutRow
                    width: layoutListView.width
                    height: 32
                    radius: 4
                    color: (modelData.name === sidebar.selectedLayoutName) ? palette.selected : palette.surfaceAlt

                    property string layoutName: modelData.name || ""

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: layoutRow.layoutName
                        color: palette.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                layoutMenu.layoutName = layoutRow.layoutName
                                layoutMenu.open()
                                return
                            }
                            sidebar.selectedLayoutName = layoutRow.layoutName
                            sidebar.navigate("loadLayout:" + layoutRow.layoutName)
                        }
                    }

                    Menu {
                        id: layoutMenu
                        property string layoutName: ""
                        MenuItem {
                            text: "Load"
                            onTriggered: {
                                sidebar.selectedLayoutName = layoutMenu.layoutName
                                sidebar.navigate("loadLayout:" + layoutMenu.layoutName)
                            }
                        }
                        MenuItem {
                            text: "Overwrite with current grid"
                            onTriggered: sidebar.navigate("saveLayoutAs:" + layoutMenu.layoutName)
                        }
                        MenuItem {
                            text: "Delete"
                            onTriggered: sidebar.navigate("deleteLayout:" + layoutMenu.layoutName)
                        }
                    }
                }
            }

            // Empty state for layouts
            Text {
                anchors.centerIn: parent
                visible: sidebar.layoutList.length === 0
                text: "No layouts"
                color: palette.textMuted
                font.pixelSize: 13
            }
        }

        // Save as…
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 4
            color: saveAsBtn.containsMouse ? palette.surfaceHover : "#333333"
            border.color: palette.border
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Save layout as…"
                color: palette.text
                font.pixelSize: 12
            }
            MouseArea {
                id: saveAsBtn
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: saveAsDialog.open()
            }
        }
    }

    // Name dialog
    Popup {
        id: saveAsDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(240, sidebar.width - 16)
        height: 110
        padding: 12
        background: Rectangle {
            color: palette.surfaceAlt
            border.color: palette.border
            radius: 6
        }

        Column {
            anchors.fill: parent
            spacing: 10

            Text {
                text: "Layout name"
                color: "#CCC"
                font.pixelSize: 12
            }
            TextField {
                id: layoutNameField
                width: parent.width
                placeholderText: "e.g. Front only"
                color: palette.text
                selectedTextColor: palette.text
                selectionColor: NxStyle.accent
                background: Rectangle {
                    color: "#1A1A1A"
                    border.color: palette.border
                    radius: 3
                }
            }
            Row {
                spacing: 8
                anchors.right: parent.right
                Rectangle {
                    width: 70
                    height: 26
                    radius: 3
                    color: "#444"
                    Text { anchors.centerIn: parent; text: "Cancel"; color: palette.text; font.pixelSize: 12 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: saveAsDialog.close()
                    }
                }
                Rectangle {
                    width: 70
                    height: 26
                    radius: 3
                    color: palette.accent
                    Text { anchors.centerIn: parent; text: "Save"; color: palette.text; font.pixelSize: 12 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var n = (layoutNameField.text || "").trim()
                            if (n.length) {
                                sidebar.navigate("saveLayoutAs:" + n)
                                sidebar.selectedLayoutName = n
                                layoutNameField.text = ""
                                saveAsDialog.close()
                            }
                        }
                    }
                }
            }
        }
        onOpened: layoutNameField.forceActiveFocus()
    }
}
