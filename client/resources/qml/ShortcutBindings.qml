import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: bindings

    property var shortcuts

    // Camera selection
    Shortcut { sequence: "1"; onActivated: shortcuts.handleKey(Qt.Key_1, Qt.NoModifier) }
    Shortcut { sequence: "2"; onActivated: shortcuts.handleKey(Qt.Key_2, Qt.NoModifier) }
    Shortcut { sequence: "3"; onActivated: shortcuts.handleKey(Qt.Key_3, Qt.NoModifier) }
    Shortcut { sequence: "4"; onActivated: shortcuts.handleKey(Qt.Key_4, Qt.NoModifier) }
    Shortcut { sequence: "5"; onActivated: shortcuts.handleKey(Qt.Key_5, Qt.NoModifier) }
    Shortcut { sequence: "6"; onActivated: shortcuts.handleKey(Qt.Key_6, Qt.NoModifier) }
    Shortcut { sequence: "7"; onActivated: shortcuts.handleKey(Qt.Key_7, Qt.NoModifier) }
    Shortcut { sequence: "8"; onActivated: shortcuts.handleKey(Qt.Key_8, Qt.NoModifier) }
    Shortcut { sequence: "9"; onActivated: shortcuts.handleKey(Qt.Key_9, Qt.NoModifier) }
    Shortcut { sequence: "0"; onActivated: shortcuts.handleKey(Qt.Key_0, Qt.NoModifier) }

    Shortcut { sequence: "Up"; onActivated: shortcuts.handleKey(Qt.Key_Up, Qt.NoModifier) }
    Shortcut { sequence: "Down"; onActivated: shortcuts.handleKey(Qt.Key_Down, Qt.NoModifier) }
    Shortcut { sequence: "Left"; onActivated: shortcuts.handleKey(Qt.Key_Left, Qt.NoModifier) }
    Shortcut { sequence: "Right"; onActivated: shortcuts.handleKey(Qt.Key_Right, Qt.NoModifier) }

    // View control
    Shortcut { sequence: "F"; onActivated: shortcuts.handleKey(Qt.Key_F, Qt.NoModifier) }
    Shortcut { sequence: "F11"; onActivated: shortcuts.handleKey(Qt.Key_F11, Qt.NoModifier) }
    Shortcut { sequence: "L"; onActivated: shortcuts.handleKey(Qt.Key_L, Qt.NoModifier) }
    Shortcut { sequence: "Esc"; onActivated: shortcuts.handleKey(Qt.Key_Escape, Qt.NoModifier) }
    Shortcut { sequence: "Tab"; onActivated: shortcuts.handleKey(Qt.Key_Tab, Qt.NoModifier) }
    Shortcut { sequence: "Shift+Tab"; onActivated: shortcuts.handleKey(Qt.Key_Tab, Qt.ShiftModifier) }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: shortcuts.handleKey(Qt.Key_Tab, Qt.ControlModifier) }
    Shortcut { sequence: "E"; onActivated: shortcuts.handleKey(Qt.Key_E, Qt.NoModifier) }
    Shortcut { sequence: "T"; onActivated: shortcuts.handleKey(Qt.Key_T, Qt.NoModifier) }
    Shortcut { sequence: "G"; onActivated: shortcuts.handleKey(Qt.Key_G, Qt.NoModifier) }
    Shortcut { sequence: "H"; onActivated: shortcuts.handleKey(Qt.Key_H, Qt.NoModifier) }
    Shortcut { sequence: "Ctrl+S"; onActivated: shortcuts.handleKey(Qt.Key_S, Qt.ControlModifier) }
    Shortcut { sequence: "F1"; onActivated: shortcuts.handleKey(Qt.Key_F1, Qt.NoModifier) }
}
