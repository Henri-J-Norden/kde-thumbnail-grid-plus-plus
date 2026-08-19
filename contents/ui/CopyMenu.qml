/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2024 Antigravity <antigravity@google.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Context menu listing copyable facts about a window (uuid, pid, exec path,
// geometry, ...). Items whose value comes from a shell command are filled in
// asynchronously: the menu emits commandRequested() and the caller feeds the
// output back through deliverResult().
Menu {
    id: root

    // tabBox.isX11Window, passed in as a function value.
    required property var isX11Window

    // Text the user chose to copy; the caller owns the Clipboard object.
    signal copyRequested(string text)
    // A Left/Right/Tab keypress the menu does not use; the grid moves selection.
    signal navigateRequested(int key)
    // Shell command whose stdout should come back via deliverResult().
    signal commandRequested(string command)

    // Routes a command's output to whichever item still has it as its `command`
    // binding. A reply for a since-changed selection matches nothing and is dropped.
    function deliverResult(sourceName, result) {
        for (let i = 0; i < root.asyncItems.length; ++i) {
            const item = root.asyncItems[i]
            if (item.command === sourceName)
                item.value = result
        }
    }

    Timer {
        id: mnemonicTimer
        property var item: null
        interval: Kirigami.Units.longDuration
        onTriggered: {
            if (mnemonicTimer.item) {
                mnemonicTimer.item.copy()
                mnemonicTimer.item = null
            }
            root.dismiss()
        }
    }

    property var sourceWindow: null
    readonly property int sourcePid: root.sourceWindow?.pid ?? 0
    property bool sticky: false
    onClosed: root.sourceWindow = null
    onOpened: {
        root.currentIndex = 0
        root.refreshProcessInfo()
    }
    property int _previousIndex: 0
    onCurrentIndexChanged: {
        if (root.currentIndex >= 0)
            root._previousIndex = root.currentIndex
        else if (root.visible)
            root.currentIndex = root._previousIndex
    }
    readonly property var asyncItems: [processPathItem, processCmdlineItem,
                                       cwdItem, scopeItem, parentItem]
    function refreshProcessInfo() {
        for (let i = 0; i < root.asyncItems.length; ++i) {
            const item = root.asyncItems[i]
            item.value = "(loading...)"
            if (item.command)
                root.commandRequested(item.command)
        }
    }
    // Must stay in the same order as the CopyItem declarations below,
    // since triggerMnemonic() maps the index onto currentIndex.
    readonly property var items: [uuidItem, pidItem, processPathItem,
                                  processCmdlineItem, captionItem, cwdItem,
                                  scopeItem, parentItem, desktopFileItem,
                                  platformItem, frameGeoItem, outputItem,
                                  desktopsItem, activitiesItem, stateItem,
                                  ruleItem]
    function triggerMnemonic(keyCode) {
        for (let i = 0; i < root.items.length; ++i) {
            const item = root.items[i]
            if (item && item.mnemonicKey && item.mnemonicKey === keyCode) {
                // Highlight first, then copy shortly after, so the
                // selection is visible before the menu closes. KWin does
                // not forward key releases, so this can't be done onReleased.
                root.currentIndex = i
                mnemonicTimer.item = item
                mnemonicTimer.restart()
                return true
            }
        }
        return false
    }
    function dismiss() {
        root.sticky = false
        root.close()
    }
    function openAt(win, pos) {
        root.sticky = true
        root.sourceWindow = win
        if (root.visible) {
            // Already shown: just move it and refresh instead of
            // close()+popup(), whose pending close transition would
            // immediately hide the freshly reopened menu.
            if (pos) {
                root.x = pos.x
                root.y = pos.y
            }
            root.refreshProcessInfo()
        } else if (pos) {
            root.popup(pos)
        } else {
            root.popup()
        }
    }
    function show(win, pos) {
        if (root.sticky) {
            root.dismiss()
        } else {
            root.openAt(win, pos)
        }
    }

    CopyMenuItem {
        id: uuidItem
        prefix: "&UUID: "
        value: String(root.sourceWindow?.internalId ?? "")
    }
    CopyMenuItem {
        id: pidItem
        prefix: "PI&D: "
        value: String(root.sourceWindow?.pid ?? "")
    }
    CopyMenuItem {
        id: processPathItem
        prefix: "Process &Path: "
        value: "(loading...)"
        command: root.sourcePid
            ? "readlink /proc/" + root.sourcePid + "/exe" : ""
    }
    CopyMenuItem {
        id: processCmdlineItem
        prefix: "Process &Args: "
        value: "(loading...)"
        command: root.sourcePid
            ? "cat /proc/" + root.sourcePid + "/cmdline | tr '\\0' ' '" : ""
    }
    CopyMenuItem {
        id: captionItem
        prefix: "Captio&n: "
        value: String(root.sourceWindow?.caption ?? "")
    }
    CopyMenuItem {
        id: cwdItem
        prefix: "&CWD: "
        value: "(loading...)"
        command: root.sourcePid
            ? "readlink /proc/" + root.sourcePid + "/cwd" : ""
    }
    CopyMenuItem {
        id: scopeItem
        prefix: "Scop&e: "
        value: "(loading...)"
        command: root.sourcePid
            ? "cat /proc/" + root.sourcePid + "/cgroup | head -n1 | sed 's|.*/||'" : ""
    }
    CopyMenuItem {
        id: parentItem
        prefix: "&Launched by: "
        value: "(loading...)"
        command: root.sourcePid
            ? "ps -o ppid=,comm= -p " + root.sourcePid + " | tr -s ' '" : ""
    }
    CopyMenuItem {
        id: desktopFileItem
        prefix: "Desktop &File: "
        value: String(root.sourceWindow?.desktopFileName ?? "")
    }
    CopyMenuItem {
        id: platformItem
        prefix: "Platfor&m: "
        value: {
            const win = root.sourceWindow
            if (!win) return ""
            return root.isX11Window(win) ? "X11/XWayland" : "Wayland"
        }
    }
    CopyMenuItem {
        id: frameGeoItem
        prefix: "Frame &Geometry: "
        value: {
            const g = root.sourceWindow?.frameGeometry
            if (!g) return ""
            return "x:" + g.x + " y:" + g.y + " w:" + g.width + " h:" + g.height
        }
    }
    CopyMenuItem {
        id: outputItem
        prefix: "&Output: "
        value: String(root.sourceWindow?.output?.name ?? "")
    }
    CopyMenuItem {
        id: desktopsItem
        prefix: "Des&ktops: "
        value: {
            const win = root.sourceWindow
            if (!win) return ""
            if (win.onAllDesktops) return "all"
            return (win.desktops || []).map(d => d.name || d.id).join(", ")
        }
    }
    CopyMenuItem {
        id: activitiesItem
        prefix: "Acti&vities: "
        value: {
            const a = root.sourceWindow?.activities
            return (a && a.length) ? a.join(", ") : "all"
        }
    }
    CopyMenuItem {
        id: stateItem
        prefix: "&State: "
        value: {
            const win = root.sourceWindow
            if (!win) return ""
            const flags = []
            if (win.minimized) flags.push("minimized")
            if (win.fullScreen) flags.push("fullScreen")
            if (win.keepAbove) flags.push("keepAbove")
            if (win.keepBelow) flags.push("keepBelow")
            if (win.noBorder) flags.push("noBorder")
            if (win.skipTaskbar) flags.push("skipTaskbar")
            if (win.skipPager) flags.push("skipPager")
            if (win.skipSwitcher) flags.push("skipSwitcher")
            if (win.demandsAttention) flags.push("demandsAttention")
            return flags.length ? flags.join(", ") : "none"
        }
    }
    CopyMenuItem {
        id: ruleItem
        prefix: "KWin &Rule: "
        value: {
            const win = root.sourceWindow
            if (!win) return ""
            const cls = String(win.resourceClass ?? "")
            return "[" + (cls || "window") + "]\n"
                 + "Description=Rule for " + (cls || "window") + "\n"
                 + "wmclass=" + cls + "\n"
                 + "wmclasscomplete=false\n"
                 + "wmclassmatch=1\n"
        }
    }
}
