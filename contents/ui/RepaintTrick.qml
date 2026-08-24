/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Window

// Forces the compositor to repaint the whole screen.
//
// Moving or resizing a window from inside KWin's own QML leaves stale frames
// behind: the window is drawn at its new position but the region it vacated is
// never damaged. Moving a transparent fullscreen window on top of everything
// damages what it leaves and what it covers, and the artifacts go away.
//
// main.qml owns the single instance and hands it to the popups that move
// windows around: trigger() for a one-off change; for a drag, show it for the
// length of the drag and damage() per event, since showing and hiding it at
// pointer rate - from inside KWin's input delivery - crashes the compositor.
Window {
    id: root

    visible: false
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    // The whole screen, not the work area: stale frames can be anywhere,
    // including behind the panels. One pixel wider than the screen, and
    // starting a pixel to its left, so the nudge in damage() never uncovers an
    // edge.
    x: -1
    width: Screen.width + 1
    height: Screen.height

    // Being shown is itself a damage event, so a one-off repaint is one
    // show/hide cycle.
    function trigger() {
        root.visible = true
        Qt.callLater(() => { root.visible = false })
    }

    // Once shown, the window damages nothing further by just sitting there -
    // a surface that commits no frames gives the compositor nothing to
    // repaint. Nudging it by a pixel does.
    function damage() {
        if (root.visible)
            root.x = root.x === 0 ? -1 : 0
    }
}
