import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: sidebar
    objectName: "Sidebar"

    property var frigateRef

    visible: isCameraPage

    width: isCameraPage
           ? (collapsed ? 0 : 260)
           : 0

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
    property real dragX: 0
    property real dragY: 0

    property string pressCameraId: ""
    property string pressCameraName: ""

    Rectangle {
        anchors.fill: parent
        color: "#202020"
    }

    Column {
        id: contentColumn
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
                    hoverEnabled: true
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
                       : "#303030"

                Row {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 10

                    // NX-style camera icon + status
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
                            // Tint: green online, red offline, white selected
                            opacity: cameraRow.isOnline ? 1.0 : 0.55
                        }

                        // Small status pip (NX-like)
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

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    pressAndHoldInterval: 200

                    onPressed: {
                        sidebar.pressCameraId = cameraId
                        sidebar.pressCameraName = cameraName
                    }

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) {
                            sidebarContextMenu.open()
                            return
                        }
                        sidebar.selectedCameraId = cameraId
                        sidebar.cameraSelected(cameraId)
                    }
                }
            }
        }
    }

    DragHandler {
        id: globalDrag
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (active) {
                if (sidebar.pressCameraId !== "") {
                    sidebar.dragging = true
                    sidebar.draggingCameraId = sidebar.pressCameraId
                    sidebar.draggingCameraName = sidebar.pressCameraName
                    let p = globalDrag.centroid && globalDrag.centroid.scenePosition
                    if (p) {
                        sidebar.dragX = p.x
                        sidebar.dragY = p.y
                    }
                }
            } else {
                if (sidebar.dragging) {
                    sidebar.cameraDropped(
                        sidebar.dragX,
                        sidebar.dragY + 40,
                        sidebar.draggingCameraName
                    )
                }
                Qt.callLater(function() {
                    sidebar.dragging = false
                    sidebar.draggingCameraName = ""
                })
            }
        }

        onTranslationChanged: {
            if (sidebar.dragging) {
                let p = globalDrag.centroid && globalDrag.centroid.scenePosition
                if (p) {
                    sidebar.dragX = p.x
                    sidebar.dragY = p.y
                }
            }
        }
    }

    Rectangle {
        id: dragGhost
        visible: sidebar.dragging
        width: 160
        height: 24
        radius: 4
        color: "#5050A0CC"
        border.color: "#A0A0FF"
        border.width: 1
        z: 100000
        x: sidebar.dragX - width / 2
        y: sidebar.dragY - height / 2 + 4

        Text {
            anchors.centerIn: parent
            text: sidebar.draggingCameraName
            color: "white"
            font.pixelSize: 14
            elide: Text.ElideRight
        }
    }
}