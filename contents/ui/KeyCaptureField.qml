/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "keyutils.js" as KeyUtils

// A read-only text field that captures the next key press and stores its
// Qt.Key_* value as an int. Used in the settings panel to let the user
// rebind keyboard shortcuts by pressing the desired key while the field
// has focus.
KwinTextField {
    id: root

    property int keyCode: 0

    signal keyCaptured()

    readOnly: true
    text: KeyUtils.keyName(root.keyCode)
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
}
