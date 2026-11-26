import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

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
    signal requestRemoveCamera(string cameraId)
    signal navigate(string page)
    signal cameraDropped(real x, real y, string cameraName)

    property var cameraList: []
    property string selectedCameraId: ""
    property string serverName: ""

    // [{ name: "…", cameras: [...] }, ...] — filled from ServerView
    property var layoutList: []
    property string selectedLayoutName: ""

    property bool dragging: false
    property string draggingCameraId: ""
    property string draggingCameraName: ""
    property real ghostX: 0
    property real ghostY: 0

    // Simple dark palette – change here to restyle the whole sidebar
    QtObject {
        id: palette
        readonly property color background: "#202020"
        readonly property color surface: "#303030"
        readonly property color surfaceAlt: "#2A2A2A"
        readonly property color surfaceHover: "#3A3A50"
        readonly property color selected: "#404060"
        readonly property color border: "#555555"
        readonly property color text: "#FFFFFF"
        readonly property color textMuted: "#AAAAAA"
        readonly property color accent: "#4060A0"
        readonly property color online: "#4CAF50"
        readonly property color offline: "#D32F2F"
        readonly property color ghostBg: "#2A2A4ADD"
        readonly property color ghostBorder: "#8B9BFF"
    }

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

        // Cameras header
        Text {
            Layout.fillWidth: true
            text: "Cameras"
            color: palette.textMuted
            font.pixelSize: 11
            font.bold: true
        }

        // Camera list (or empty state)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1   // stretch weight

            ListView {
                id: cameraListView
                anchors.fill: parent
                clip: true
                visible: sidebar.cameraList.length > 0
                model: sidebar.cameraList

                delegate: Rectangle {
                    id: cameraRow
                    width: cameraListView.width
                    height: 40
                    radius: 4

                    property string cameraId: modelData.id || ""
                    property string cameraName: modelData.name || ""
                    property bool isOnline: false

                    Component.onCompleted: {
                        isOnline = frigateRef ? frigateRef.isCameraOnline(cameraId) : false
                    }

                    Connections {
                        target: frigateRef
                        ignoreUnknownSignals: true
                        function onCameraOnline(name) {
                            if (name === cameraId || name === cameraName)
                                cameraRow.isOnline = true
                        }
                        function onCameraOffline(name) {
                            if (name === cameraId || name === cameraName)
                                cameraRow.isOnline = false
                        }
                    }

                    color: (cameraId === sidebar.selectedCameraId)
                           ? palette.selected
                           : (sidebar.dragging && sidebar.draggingCameraId === cameraId)
                             ? palette.surfaceHover
                             : palette.surface

                    opacity: (sidebar.dragging && sidebar.draggingCameraId === cameraId) ? 0.5 : 1.0

                    Row {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10
                        z: 0

                        Item {
                            width: 22
                            height: 22
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: "qrc:/app/assets/icons/nx/cameras.svg"
                                fillMode: Image.PreserveAspectFit
                                opacity: cameraRow.isOnline ? 1.0 : 0.55
                            }
                            Rectangle {
                                width: 7
                                height: 7
                                radius: 3.5
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                color: cameraRow.isOnline ? palette.online : palette.offline
                                border.color: palette.background
                                border.width: 1
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cameraName
                            color: palette.text
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            width: cameraRow.width - 56
                        }
                    }

                    Menu {
                        id: sidebarContextMenu
                        title: cameraName !== "" ? cameraName : "Camera"
                        MenuItem {
                            text: "Select"
                            enabled: cameraName !== ""
                            onTriggered: {
                                sidebar.selectedCameraId = cameraId
                                sidebar.cameraSelected(cameraId)
                            }
                        }
                        MenuItem {
                            text: "Edit Camera"
                            enabled: cameraName !== ""
                            onTriggered: {
                                sidebar.selectedCameraId = cameraId
                                sidebar.cameraSelected(cameraId)
                                sidebar.navigate("editCamera:" + cameraId)
                            }
                        }
                        MenuItem {
                            text: "Remove Camera"
                            onTriggered: sidebar.requestRemoveCamera(cameraId)
                        }
                        MenuItem {
                            text: "Add Camera"
                            onTriggered: sidebar.navigate("addCamera")
                        }
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: {
                            sidebar.selectedCameraId = cameraId
                            sidebar.cameraSelected(cameraId)
                        }
                    }

                    DragHandler {
                        id: rowDrag
                        target: null
                        acceptedButtons: Qt.LeftButton
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                            | PointerHandler.ApprovesTakeOverByAnything

                        function syncGhost() {
                            if (!rowDrag.centroid)
                                return
                            var scene = rowDrag.centroid.scenePosition
                            if (!scene)
                                return
                            var loc = sidebar.mapFromItem(null, scene.x, scene.y)
                            sidebar.ghostX = loc.x + 10
                            sidebar.ghostY = loc.y + 10
                        }

                        onActiveChanged: {
                            if (active) {
                                sidebar.dragging = true
                                sidebar.draggingCameraId = cameraId
                                sidebar.draggingCameraName = cameraName
                                syncGhost()
                            } else if (sidebar.draggingCameraId === cameraId) {
                                var scene = rowDrag.centroid ? rowDrag.centroid.scenePosition : null
                                if (scene) {
                                    var loc = sidebar.mapFromItem(null, scene.x, scene.y)
                                    var g = sidebar.mapToGlobal(loc.x, loc.y)
                                    sidebar.cameraDropped(g.x, g.y, sidebar.draggingCameraName)
                                }
                                sidebar.dragging = false
                                sidebar.draggingCameraId = ""
                                sidebar.draggingCameraName = ""
                            }
                        }

                        onTranslationChanged: {
                            if (active)
                                syncGhost()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        z: 10
                        onClicked: sidebarContextMenu.open()
                    }
                }
            }

            // Empty state for cameras
            Text {
                anchors.centerIn: parent
                visible: sidebar.cameraList.length === 0
                text: "No cameras"
                color: palette.textMuted
                font.pixelSize: 13
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
                selectionColor: palette.accent
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

    // Drag ghost
    Rectangle {
        id: dragGhost
        visible: sidebar.dragging
        width: Math.min(220, Math.max(130, ghostLabel.implicitWidth + 48))
        height: 34
        radius: 6
        z: 100000
        x: sidebar.ghostX
        y: sidebar.ghostY
        color: palette.ghostBg
        border.color: palette.ghostBorder
        border.width: 1

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 8

            Image {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                source: "qrc:/app/assets/icons/nx/cameras.svg"
                fillMode: Image.PreserveAspectFit
            }
            Text {
                id: ghostLabel
                anchors.verticalCenter: parent.verticalCenter
                text: sidebar.draggingCameraName
                color: palette.text
                font.pixelSize: 13
                font.bold: true
            }
        }
    }
}