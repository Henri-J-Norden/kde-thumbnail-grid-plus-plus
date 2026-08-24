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
// never damaged. Flashing a transparent fullscreen window on top for one event
// loop turn damages everything and the artifacts go away.
//
// main.qml owns the single instance and hands it to the popups that move
// windows around (EditPopup's geometry fields, the settings panel's title-bar
// drag); they call trigger() after each change.
Window {
    id: root

    // The full screen, not the work area: stale frames can be anywhere,
    // including behind the panels.
    property int screenW: 1920
    property int screenH: 1080

    visible: false
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    x: 0
    y: 0
    width: root.screenW
    height: root.screenH

    // Cheap enough to call on every drag event: while visible is already true
    // the extra callLater just re-arms the hide, so a burst of calls collapses
    // into one flash that lasts as long as the drag does.
    function trigger() {
        root.visible = true
        Qt.callLater(() => { root.visible = false })
    }
}
