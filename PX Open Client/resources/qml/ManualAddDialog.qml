import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Dialog {
    id: dialog
    modal: true
    title: "Add Server Manually"
    standardButtons: Dialog.Ok | Dialog.Cancel

    property string serverName: ""
    property string serverAddress: ""

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        TextField {
            id: nameField
            placeholderText: "Server Name"
            Layout.fillWidth: true
        }

        TextField {
            id: addressField
            placeholderText: "Server Address"
            Layout.fillWidth: true
        }
    }

    onAccepted: {
        serverName = nameField.text
        serverAddress = addressField.text
        console.log("Manual server added:", serverName, serverAddress)
    }
}
