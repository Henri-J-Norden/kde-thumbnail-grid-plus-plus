/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick

// Drags to move or resize `target`, which can be a Window or a Popup - both
// expose the same x/y/width/height. Anchor it over whatever should be grabbable
// (a title bar, a corner grip).
Item {
    id: root

    // What to move or resize. Nothing happens while this is null, which is the
    // case for a moment when a hosting window is being torn down.
    property var target: null

    // Move by default; resize from the top-left-anchored corner instead.
    property bool resize: false

    // Whether this drag area sits inside the thing it moves - true for a
    // window's own title bar, false for a popup positioned within some other,
    // stationary window. It decides how the reported translation is read; see
    // the move branch below.
    property bool insideTarget: false

    property real minimumWidth: 0
    property real minimumHeight: 0

    // Moving a window from inside KWin leaves stale frames behind, so the
    // screen is repainted for as long as the drag lasts. See RepaintTrick.
    property var repaintTrick: null

    DragHandler {
        target: null

        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0

        onActiveChanged: {
            if (root.repaintTrick)
                root.repaintTrick.visible = active
            if (active && root.target) {
                startX = root.target.x
                startY = root.target.y
                startW = root.target.width
                startH = root.target.height
            }
        }

        onActiveTranslationChanged: {
            if (!active || !root.target)
                return
            if (root.resize) {
                // Resizing leaves the top-left corner in place, so the
                // coordinate system this translation is measured in does not
                // move: the plain start + translation form is correct.
                root.target.width = Math.max(root.minimumWidth, startW + activeTranslation.x)
                root.target.height = Math.max(root.minimumHeight, startH + activeTranslation.y)
            } else if (root.insideTarget) {
                // The translation is measured in a frame that moves with the
                // target, so once it has moved by d the reported travel is the
                // cursor's minus d - assigning start + translation would
                // settle at half the cursor's travel. Adding the *remaining*
                // translation to the current position cancels exactly: the
                // target ends up displaced by the full travel, the next event
                // reports zero, and it stays put. 1:1 and self-correcting.
                root.target.x += activeTranslation.x
                root.target.y += activeTranslation.y
            } else {
                // Here the frame stays put while the target moves, so the
                // translation is the whole cursor travel every event and the
                // plain form is the correct one. Adding it would compound.
                root.target.x = startX + activeTranslation.x
                root.target.y = startY + activeTranslation.y
            }
            root.repaintTrick?.damage()
        }
    }
}
