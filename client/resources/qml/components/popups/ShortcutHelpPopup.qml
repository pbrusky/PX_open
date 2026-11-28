import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import PxOpen 1.0

Popup {
    id: popup
    modal: true
    focus: true
    anchors.centerIn: parent
    width: 460
    height: 430
    padding: 0

    signal closeRequested()

    background: Rectangle {
        color: NxStyle.surfaceAlt
        border.color: NxStyle.borderStrong
        radius: 8
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Keyboard shortcuts"
                color: NxStyle.text
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }
            Image {
                width: 14
                height: 14
                fillMode: Image.PreserveAspectFit
                source: "qrc:/app/assets/icons/nx/close.svg"
                opacity: closeArea.containsMouse ? 1.0 : 0.55
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        popup.close()
                        popup.closeRequested()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: NxStyle.border
        }

        ListModel {
            id: shortcutsModel
            Component.onCompleted: {
                append({ keys: "1 – 9, 0", action: "Select camera 1–9 (0 = 10th) and add it to the grid" })
                append({ keys: "↑ / ↓", action: "Select previous / next camera" })
                append({ keys: "← / →", action: "Seek ±10 s in fullscreen playback, otherwise select camera" })
                append({ keys: "F / F11", action: "Toggle fullscreen for the selected camera" })
                append({ keys: "L", action: "Return to live view" })
                append({ keys: "Esc", action: "Leave fullscreen / close dialogs" })
                append({ keys: "Tab", action: "Toggle the camera tree" })
                append({ keys: "Shift + Tab", action: "Toggle the events panel" })
                append({ keys: "Ctrl + Tab / T", action: "Toggle the timeline" })
                append({ keys: "E", action: "Toggle the events panel" })
                append({ keys: "G / H", action: "Go to grid / home page" })
                append({ keys: "Ctrl + S", action: "Save current grid as the Default layout" })
                append({ keys: "F1", action: "Show this shortcut list" })
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: shortcutsModel
            spacing: 2
            delegate: RowLayout {
                width: ListView.view.width
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 108
                    Layout.preferredHeight: 24
                    radius: 4
                    color: NxStyle.surface
                    border.color: NxStyle.border
                    Text {
                        anchors.centerIn: parent
                        text: model.keys
                        color: NxStyle.text
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: model.action
                    color: NxStyle.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }

        Button {
            Layout.alignment: Qt.AlignRight
            text: "Close"
            onClicked: {
                popup.close()
                popup.closeRequested()
            }
        }
    }
}
