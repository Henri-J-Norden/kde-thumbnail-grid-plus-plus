/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import org.kde.plasma.components 3.0 as PlasmaComponents3

// A TextField that can still be typed into while hosted inside KWin.
//
// The switcher's QML runs in the KWin process, so its windows are internal
// windows: KWin synthesises the QKeyEvents itself and sends them straight to
// the QQuickWindow. Those events carry a key code and modifiers but an empty
// text() string, and Qt's TextInput only inserts a character when
// QInputControl::isAcceptableInput() sees non-empty text. That is why editing
// keys (backspace, delete, arrows, Ctrl+V) work in the switcher while ordinary
// characters silently do nothing - and why everything works in the System
// Settings preview, which is hosted by a normal application window.
//
// So when a key arrives without text, reconstruct the character from the key
// code and insert it by hand. Events that do carry text are left alone, which
// keeps the normal host (and its input method) working unchanged.
//
// Limitations of the fallback path: it assumes a US-ASCII layout, and dead
// keys, AltGr and input methods are not reachable at all - KWin never gives an
// internal window a text-input focus. Fine for the short numeric/search
// entries here, not a general-purpose text editor.
PlasmaComponents3.TextField {
    id: root

    readonly property var shiftedAscii: ({
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
        "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
        "-": "_", "=": "+", "[": "{", "]": "}", "\\": "|",
        ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~"
    })

    // "" when the key carries no printable character of its own (modifiers held,
    // function keys, navigation keys - all of which TextInput handles by key code).
    function charForKey(key, modifiers) {
        if (modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return ""
        // Qt's key codes for printable ASCII are the unshifted character, with
        // letters as uppercase.
        if (key < 0x20 || key > 0x7e)
            return ""
        const base = String.fromCharCode(key)
        const isLetter = key >= Qt.Key_A && key <= Qt.Key_Z
        if (modifiers & Qt.ShiftModifier)
            return isLetter ? base : (shiftedAscii[base] !== undefined ? shiftedAscii[base] : base)
        return isLetter ? base.toLowerCase() : base
    }

    Keys.onPressed: (event) => {
        if (event.text.length > 0)
            return  // normal host: let TextInput insert it
        if (readOnly)
            return
        const ch = charForKey(event.key, event.modifiers)
        if (!ch)
            return
        if (selectionStart !== selectionEnd)
            remove(selectionStart, selectionEnd)
        if (maximumLength >= 0 && length >= maximumLength) {
            event.accepted = true
            return
        }
        insert(cursorPosition, ch)
        // insert() is a programmatic edit, so TextInput does not emit this for
        // us - but call sites bind through onTextEdited exactly as they would
        // for a normal keystroke.
        textEdited()
        event.accepted = true
    }
}
