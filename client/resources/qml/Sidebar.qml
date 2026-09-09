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

    property bool dragging: false
    property string draggingCameraId: ""
    property string draggingCameraName: ""
    property real ghostX: 0
    property real ghostY: 0

    Rectangle {
        anchors.fill: parent
        color: "#202020"
    }

    Column {
        spacing: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8

        Item {
            width: parent.width
            height: 28

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
                    color: "white"
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

        ListView {
            id: cameraListView
            width: parent.width
            height: sidebar.height - 60
            clip: true
            model: sidebar.cameraList

            delegate: Rectangle {
                id: cameraRow
                width: cameraListView.width
                height: 40
                radius: 4

                property string cameraId: modelData.id
                property string cameraName: modelData.name
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
                       ? "#404060"
                       : (sidebar.dragging && sidebar.draggingCameraId === cameraId)
                         ? "#3A3A50"
                         : "#303030"

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
                            color: cameraRow.isOnline ? "#4CAF50" : "#D32F2F"
                            border.color: "#202020"
                            border.width: 1
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cameraName
                        color: "white"
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
    }

    Rectangle {
        id: dragGhost
        visible: sidebar.dragging
        width: Math.min(220, Math.max(130, ghostLabel.implicitWidth + 48))
        height: 34
        radius: 6
        z: 100000
        x: sidebar.ghostX
        y: sidebar.ghostY
        color: "#2A2A4ADD"
        border.color: "#8B9BFF"
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
                color: "white"
                font.pixelSize: 13
                font.bold: true
            }
        }
    }
}