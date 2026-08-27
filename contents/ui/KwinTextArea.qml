/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import "keyutils.js" as KeyUtils

// The multi-line counterpart of KwinTextField - see that file for why typing
// has to be reconstructed by hand inside KWin's internal windows. Return and
// Enter are part of that: they reach the switcher with an empty text() too, so
// without this a newline could not be typed either.
//
// TextArea has no textEdited signal (TextEdit does not provide one), so call
// sites bind through onTextChanged instead.
TextArea {
    id: root

    Keys.onPressed: (event) => {
        if (!KeyUtils.insertKeyEvent(root, event, true))
            return
        event.accepted = true
    }
}
