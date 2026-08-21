/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// One copyable fact in CopyMenu. Reaches the owning menu through MenuItem's
// built-in `menu` property for the shared mnemonic/dismiss/copy handling, so
// it is only usable inside a CopyMenu.
MenuItem {
    id: root

    // MenuItem.menu is typed as plain Menu; narrow it so the CopyMenu members
    // used below are checkable rather than resolved dynamically at runtime.
    readonly property CopyMenu owner: root.menu as CopyMenu

    function escapeHtml(s) {
        return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // "&" marks the mnemonic character, e.g. "Process &Path: "
    property string prefix: ""
    property string value: ""
    // Shell command whose stdout fills `value`; "" for static items.
    // Deliberately a binding on sourceWindow: when the selection moves
    // this re-evaluates, so a reply that arrives late for the previously
    // selected window matches no item and is discarded.
    property string command: ""
    readonly property int mnemonicIndex: prefix.indexOf("&")
    readonly property string plainPrefix: prefix.replace("&", "")
    readonly property string mnemonic: mnemonicIndex >= 0 && mnemonicIndex + 1 < prefix.length
                                       ? prefix[mnemonicIndex + 1] : ""
    // KWin delivers synthesized key events without event.text, so match
    // on the key code: for letters/digits it equals the uppercase char code.
    readonly property int mnemonicKey: mnemonic ? mnemonic.toUpperCase().charCodeAt(0) : 0
    text: plainPrefix + value
    function copy() {
        root.owner.copyRequested(root.value)
    }
    onTriggered: root.copy()
    contentItem: Label {
        text: {
            const raw = root.plainPrefix
            const i = root.mnemonicIndex
            let head = root.escapeHtml(raw)
            if (i >= 0 && i < raw.length) {
                head = root.escapeHtml(raw.slice(0, i))
                      + "<u>" + root.escapeHtml(raw[i]) + "</u>"
                      + root.escapeHtml(raw.slice(i + 1))
            }
            return head + root.escapeHtml(root.value)
        }
        textFormat: Text.StyledText
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.copy()
            root.owner.dismiss()
            event.accepted = true
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape) {
            root.owner.dismiss()
            event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                   || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.owner.navigateRequested(event.key)
            event.accepted = true
        } else if (root.owner.triggerMnemonic(event.key)) {
            event.accepted = true
        }
    }
}
