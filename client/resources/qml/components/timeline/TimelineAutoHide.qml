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
            // Do not auto-hide while the calendar is open or forceVisible is true
            if (forceVisible)
                return

            if (timeline && timeline.calendarPopup && timeline.calendarPopup.visible)
                return

            // Also keep open if user is actively interacting with the timeline
            if (timeline && timeline.pointerInside)
                return

            if (timeline)
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
            if (timeline)
                timeline.collapsed = false
            autoHideTimer.restart()
            autoHide.mouseNearBottom()
        }

        onExited: {
            autoHide.mouseAway()
        }
    }
}