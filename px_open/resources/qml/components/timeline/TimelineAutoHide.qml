import QtQuick 2.15

Item {
    id: autoHide
    anchors.fill: parent

    signal mouseNearBottom()
    signal mouseAway()

    property var timeline
    property var scrubber
    property var mouseHandler

    property bool forceVisible: false
    property int autoHideDelay: 2500

    Timer {
        id: autoHideTimer
        interval: autoHideDelay
        repeat: false
        onTriggered: {
            if (!forceVisible)
                timeline.collapsed = true
        }
    }

    MouseArea {
        id: idleDetector
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        visible: true

        onPositionChanged: autoHideTimer.restart()
    }

    MouseArea {
        id: edgeDetector
        width: parent.width
        height: 8
        anchors.bottom: parent.bottom
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        visible: true
        z: 99999

        onEntered: {
            timeline.collapsed = false
            autoHideTimer.restart()
            autoHide.mouseNearBottom()
        }

        onExited: {
            autoHide.mouseAway()
        }
    }

    Rectangle {
        id: collapseHandle
        width: 32
        height: 16
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        color: "#222"
        border.color: "#444"
        border.width: 1
        z: 200
        visible: !timeline.collapsed

        Text {
            anchors.centerIn: parent
            text: "▼"
            color: "#ccc"
            font.pixelSize: 12
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                forceVisible = !forceVisible
                timeline.collapsed = !timeline.collapsed
                if (!timeline.collapsed)
                    autoHideTimer.restart()
            }
        }
    }
}
