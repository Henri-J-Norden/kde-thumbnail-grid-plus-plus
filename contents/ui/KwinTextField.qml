/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import "keyutils.js" as KeyUtils

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
// code and insert it by hand (KeyUtils.insertKeyEvent). Events that do carry
// text are left alone, which keeps the normal host (and its input method)
// working unchanged.
//
// Limitations of the fallback path: it assumes a US-ASCII layout, and dead
// keys, AltGr and input methods are not reachable at all - KWin never gives an
// internal window a text-input focus. Fine for the short numeric/search
// entries here, not a general-purpose text editor.
TextField {
    id: root

    padding: 0
    implicitHeight: fontMetrics.height + 4
    FontMetrics { id: fontMetrics; font: root.font }

    Keys.onPressed: (event) => {
        if (!KeyUtils.insertKeyEvent(root, event, false))
            return
        // insert() is a programmatic edit, so TextInput does not emit this for
        // us - but call sites bind through onTextEdited exactly as they would
        // for a normal keystroke.
        textEdited()
        event.accepted = true
    }
}
