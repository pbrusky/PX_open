import QtQuick 2.15
import QtQuick.Controls 2.15
import PxOpen 1.0

Item {
    id: overlay
    anchors.fill: parent

    property string cameraName: ""
    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""
    property bool isOnline: true
    property bool selected: false

    signal infoRequested()
    signal removeRequested()

    readonly property color plate: "#000000E6"
    readonly property color plateText: "#F1F3F5"

    HoverHandler {
        id: hover
    }

    // The cursor can be hidden while idle; don't keep the hover chrome on.
    property bool hovered: hover.hovered && !FullscreenHelper.cursorHidden

    // ------------------------------------------------------------------
    // Motion / event flash
    // ------------------------------------------------------------------
    property bool motionActive: false
    property real _lastFlashMs: 0

    function flashMotion() {
        var now = Date.now()
        if (now - _lastFlashMs < 10000)
            return
        _lastFlashMs = now
        motionActive = true
        flashTimer.restart()
    }

    Timer {
        id: flashTimer
        interval: 1400
        repeat: false
        onTriggered: overlay.motionActive = false
    }

    // Selection / hover / motion border
    Rectangle {
        anchors.fill: parent
        radius: 1
        color: "transparent"
        border.width: (overlay.selected || overlay.hovered || overlay.motionActive) ? 2 : 0
        border.color: overlay.motionActive ? NxStyle.warning : NxStyle.accent
        opacity: (overlay.selected || overlay.hovered || overlay.motionActive) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        z: 5
    }

    // ------------------------------------------------------------------
    // Top-left: camera name on a flat plate, with status dot
    // ------------------------------------------------------------------
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 4
        anchors.topMargin: 30
        height: 22
        width: nameRow.implicitWidth + 18
        color: overlay.plate
        border.color: "#00000066"
        border.width: 1
        visible: overlay.cameraName !== ""
        z: 7

        Row {
            id: nameRow
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                width: 6
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: overlay.isOnline ? NxStyle.online : NxStyle.offline
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: overlay.cameraName
                color: overlay.plateText
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    // ------------------------------------------------------------------
    // Top-right: live clock + square hover controls
    // ------------------------------------------------------------------
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 4
        spacing: 4
        z: 10

        Rectangle {
            width: clockText.implicitWidth + 16
            height: 22
            color: overlay.plate
            border.color: "#00000066"
            border.width: 1

            Text {
                id: clockText
                anchors.centerIn: parent
                color: "#D6DAE0"
                font.pixelSize: 11
                text: ""
            }
        }

        Rectangle {
            width: 22
            height: 22
            radius: 1
            color: infoArea.containsMouse ? NxStyle.surfaceHover : overlay.plate
            border.color: "#00000066"
            border.width: 1
            opacity: overlay.hovered ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Image {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "qrc:/app/assets/icons/nx/info.svg"
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: infoArea
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                onClicked: overlay.infoRequested()
            }
        }

        Rectangle {
            width: 22
            height: 22
            radius: 1
            color: closeArea.containsMouse ? "#5A1A1A" : overlay.plate
            border.color: "#00000066"
            border.width: 1
            opacity: overlay.hovered ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Image {
                anchors.centerIn: parent
                width: 14
                height: 14
                source: "qrc:/app/assets/icons/nx/close.svg"
                fillMode: Image.PreserveAspectFit
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                onClicked: overlay.removeRequested()
            }
        }
    }

    // ------------------------------------------------------------------
    // Bottom-right: stream stats, only on hover
    // ------------------------------------------------------------------
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 4
        anchors.bottomMargin: 4
        height: 22
        width: statsText.implicitWidth + 16
        color: overlay.plate
        border.color: "#00000066"
        border.width: 1
        opacity: overlay.hovered && (resolution !== "" || fps > 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        z: 7

        Text {
            id: statsText
            anchors.centerIn: parent
            color: "#D6DAE0"
            font.pixelSize: 11
            text: {
                var parts = []
                if (resolution !== "")
                    parts.push(resolution)
                if (fps > 0)
                    parts.push(fps.toFixed(0) + " fps")
                if (bitrateKbps > 0)
                    parts.push(bitrateKbps + " kbps")
                if (codec !== "")
                    parts.push(codec.toUpperCase())
                return parts.join("  ·  ")
            }
        }
    }

    Timer {
        id: clockTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "MM/dd hh:mm:ss")
    }

    Component.onCompleted: clockText.text = Qt.formatDateTime(new Date(), "MM/dd hh:mm:ss")
}
