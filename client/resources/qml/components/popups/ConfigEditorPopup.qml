import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: popupRoot
    objectName: "ConfigEditorPopup"
    anchors.fill: parent
    z: 999999

    signal closeRequested()

    property var popupManager
    property var frigateRef
    property string configType: "frigate"
    property string filePath: ""
    property string statusText: ""
    property bool loading: false
    property bool saving: false

    function titleText() {
        return configType === "go2rtc" ? "Edit go2rtc config" : "Edit Frigate config.yml"
    }

    function loadConfig() {
        if (!frigateRef) return
        loading = true
        statusText = "Loading..."
        if (configType === "go2rtc")
            frigateRef.loadGo2rtcConfig()
        else
            frigateRef.loadFrigateConfig()
    }

    function saveConfig(doRestart) {
        if (!frigateRef) return
        saving = true
        statusText = doRestart ? "Saving and restarting..." : "Saving..."
        if (configType === "go2rtc")
            frigateRef.saveGo2rtcConfig(editor.text, doRestart)
        else
            frigateRef.saveFrigateConfig(editor.text, doRestart)
    }

    Component.onCompleted: loadConfig()

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onFrigateConfigLoaded(ok, content, path, message) {
            if (popupRoot.configType !== "frigate") return
            loading = false
            filePath = path || ""
            if (ok) {
                editor.text = content
                statusText = path ? ("Loaded: " + path) : "Loaded"
            } else {
                statusText = message || "Load failed"
            }
        }

        function onFrigateConfigSaved(ok, message) {
            if (popupRoot.configType !== "frigate") return
            saving = false
            statusText = message || (ok ? "Saved" : "Save failed")
        }

        function onGo2rtcConfigLoaded(ok, content, path, message) {
            if (popupRoot.configType !== "go2rtc") return
            loading = false
            filePath = path || ""
            if (ok) {
                editor.text = content
                statusText = path ? ("Loaded: " + path) : "Loaded"
            } else {
                statusText = message || "Load failed"
            }
        }

        function onGo2rtcConfigSaved(ok, message) {
            if (popupRoot.configType !== "go2rtc") return
            saving = false
            statusText = message || (ok ? "Saved" : "Save failed")
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: Math.min(parent.width - 40, 900)
        height: Math.min(parent.height - 40, 700)
        radius: 6
        color: "#111"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: popupRoot.titleText()
                color: "white"
                font.pixelSize: 22
                font.bold: true
            }

            Text {
                text: filePath !== "" ? filePath : " "
                color: "#aaa"
                font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            Text {
                text: "Invalid YAML can stop Frigate. A backup is created on the server before save."
                color: "#f0c040"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                TextArea {
                    id: editor
                    width: container.width - 48
                    height: Math.max(implicitHeight, 400)
                    wrapMode: TextEdit.NoWrap
                    selectByMouse: true
                    font.family: "Consolas"
                    font.pixelSize: 13
                    color: "#e0e0e0"
                    background: Rectangle { color: "#1a1a1a"; radius: 4 }
                    readOnly: popupRoot.loading || popupRoot.saving
                }
            }

            Text {
                text: statusText
                color: "#9cdcfe"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Reload"
                    enabled: !loading && !saving
                    onClicked: loadConfig()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Save"
                    enabled: !loading && !saving
                    onClicked: saveConfig(false)
                }

                Button {
                    text: "Save & Restart"
                    enabled: !loading && !saving
                    onClicked: saveConfig(true)
                }

                Button {
                    text: "Close"
                    onClicked: {
                        if (popupManager && popupManager.closePopup)
                            popupManager.closePopup()
                        closeRequested()
                    }
                }
            }
        }
    }
}