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
        if (currentPopup) {
            currentPopup.destroy()
            currentPopup = null
        }

        let comp = Qt.createComponent(path)
        if (comp.status !== Component.Ready) {
            console.error("PopupManager: failed to load", path)
            return
        }

        let obj = comp.createObject(popupManager, params || {})
        if (!obj) {
            console.error("PopupManager: failed to create popup object")
            return
        }

        currentPopup = obj

        if (obj.closeRequested) {
            obj.closeRequested.connect(closePopup)
        }

        popupOpened(path)
    }

    function closePopup() {
        if (!currentPopup)
            return

        currentPopup.destroy()
        currentPopup = null
    }
}
