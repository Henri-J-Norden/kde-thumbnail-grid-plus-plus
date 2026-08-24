/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

// A read-only text field that captures the next key press and stores its
// Qt.Key_* value as an int. Used in the settings panel to let the user
// rebind keyboard shortcuts by pressing the desired key while the field
// has focus.
KwinTextField {
    id: root

    property int keyCode: 0

    signal keyCaptured()

    readOnly: true
    text: root.keyName(root.keyCode)
    horizontalAlignment: Text.AlignHCenter
    font.family: "monospace"
    placeholderText: "—"

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Escape
            || event.key === Qt.Key_Backspace
            || event.key === Qt.Key_Shift || event.key === Qt.Key_Control
            || event.key === Qt.Key_Alt || event.key === Qt.Key_Meta)
            return
        root.keyCode = event.key
        event.accepted = true
        root.keyCaptured()
    }

    function keyName(key) {
        if (key === 0) return "—"
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9)
            return String.fromCharCode(key)
        const special = {
            [Qt.Key_PageUp]: "PgUp", [Qt.Key_PageDown]: "PgDn",
            [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
            [Qt.Key_Delete]: "Del", [Qt.Key_Space]: "Space",
            [Qt.Key_Insert]: "Ins", [Qt.Key_Return]: "Ret",
            [Qt.Key_Enter]: "Enter", [Qt.Key_Tab]: "Tab",
            [Qt.Key_Backtab]: "BkTab", [Qt.Key_Escape]: "Esc",
            [Qt.Key_Backspace]: "BkSp",
        }
        if (special[key]) return special[key]
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35)
            return "F" + (key - Qt.Key_F1 + 1)
        return "Key_" + key
    }
}
