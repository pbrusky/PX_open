import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: popupManager
    anchors.fill: parent
    z: 999999

    property var currentPopup: null

    signal popupOpened(string type)
    signal popupClosed(string type)

    function openPopup(path, params) {
        closePopup()

        var comp = Qt.createComponent(path)
        if (comp.status === Component.Loading)
            comp.statusChanged.connect(function() {
                if (comp.status === Component.Ready)
                    finishOpen(comp, path, params)
                else if (comp.status === Component.Error)
                    console.error("PopupManager: failed to load", path, comp.errorString())
            })
        else if (comp.status === Component.Ready)
            finishOpen(comp, path, params)
        else
            console.error("PopupManager: failed to load", path, comp.errorString())
    }

    function finishOpen(comp, path, params) {
        var obj = comp.createObject(popupManager, params || {})
        if (!obj) {
            console.error("PopupManager: failed to create popup object")
            return
        }

        currentPopup = obj

        if (obj.closeRequested)
            obj.closeRequested.connect(closePopup)

        popupOpened(path)
    }

    function closePopup() {
        if (!currentPopup)
            return

        var popup = currentPopup
        currentPopup = null

        if (popup.closeRequested) {
            try { popup.closeRequested.disconnect(closePopup) } catch (e) {}
        }

        popup.visible = false
        popup.destroy()
        popupClosed("")
    }

    function openRestartFrigatePopup(params) {
        // Prefer dedicated restart overlay on MainWindow, not this manager
        openPopup("qrc:/app/resources/qml/components/popups/RestartPopup.qml", params)
    }
}