/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2024 Antigravity <antigravity@google.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtCore
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.ksvg as KSvg
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons

KWin.TabBoxSwitcher {
    id: tabBox

    property int pendingIndex: -1

    // KWin 6 no longer exposes x11Window/windowId to QML, so the only reliable
    // discriminator is the C++ class name leaking through QObject's toString().
    function isX11Window(win) {
        return win ? /X11Window/.test(String(win)) : false
    }

    function parseAspectRatio(input) {
        const s = (input || "").trim()
        if (!s) return 0
        if (s.includes(":")) {
            const parts = s.split(":")
            if (parts.length === 2) {
                const x = parseFloat(parts[0])
                const y = parseFloat(parts[1])
                if (!isNaN(x) && !isNaN(y) && x > 0 && y > 0)
                    return x / y
            }
            return 0
        }
        const v = parseFloat(s)
        return (!isNaN(v) && v > 0) ? v : 0
    }

    function toFractionString(value) {
        if (value <= 0) return "0"
        const tolerance = 0.005
        let bestN = 0, bestD = 1
        for (let d = 1; d <= 30; ++d) {
            const n = Math.round(value * d)
            if (n > 50) continue
            if (d > 0 && Math.abs(n / d - value) < tolerance) {
                bestN = n
                bestD = d
                break
            }
        }
        if (bestN > 0)
            return bestN + ":" + bestD
        return value.toFixed(2)
    }

    Settings {
        id: settings
        category: tabBox.isAlternative ? "Alt" : "Main"
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwin_thumbnail_grid_plus.ini"
        property bool hoverSelection: true
        property int thumbnailWidthGridUnits: 16
        property string thumbnailHeightInput: "16:10"
        property int iconSizeIndex: 4
        property real opacityBackground: 0.5
        property real opacityThumbnail: 1.0
        property int previewRepeatCount: 1
        property string maxGridAspectRatioInput: "21:9"
        property int minimizedItalics: 1
        property int minimizedBlur: 2
        property int minimizedContrast: 1
        property int minimizedThumbnailOpacity: 0
        property int minimizedThumbnailScale: 0
        property int minimizedThumbnailRotation: 2
        property int minimizedIconOpacity: 1
        property int minimizedStrikethrough: 0
        property int minimizedUnderline: 0
        property int minimizedIcon: 0
        property real opacityWindowButton: 0.75
        property bool showSettingsButton: true
        property int buttonMaximize: 2
        property int buttonFullscreen: 1
        property int buttonNoBorder: 1
        property int buttonMinimize: 2
        property int buttonPin: 1
        property int buttonKeepAbove: 1
        property int buttonKeepBelow: 0
        property int buttonIncognito: 0
        property int buttonDemandsAttention: 4
        property int buttonShaded: 0  // Broken on wayland https://bugs.kde.org/show_bug.cgi?id=377162
        property int buttonTransparency: 4
        property int buttonSkipTaskbar: 4
        property int buttonSkipPager: 4
        property int buttonSkipSwitcher: 4
        property real opacityWindow: 0.7
        property bool buttonClose: true
        property bool buttonDebug: false
        property real buttonSize: 1.6
        property bool centerHighlightButtons: true
        property bool showProtocol: true
    }

    readonly property real buttonSize: Kirigami.Units.gridUnit * settings.buttonSize
    readonly property bool isAlternative: false  // tabBox.mode is undefined
    readonly property bool isPreview: tabBox.automaticallyHide === undefined
    readonly property bool showPreview: isPreview || showSettings
    property bool showSettings: false
    property bool animationFinished: false

    onShowPreviewChanged: {
        if (showPreview)
            settingsWnd.forceActiveFocus()
        else
            dialogMainItem.forceActiveFocus()
    }

    function dumpProperties(obj) {
        var lines = []
        for (var key in obj) {
            var v = obj[key]
            if (typeof v === "function")  // skip methods and signals
                continue
            lines.push(key + ": " + v)
        }
        return lines.join("\n")
    }

    Window {
        id: wrapper
        visible: tabBox.visible
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
        color: "transparent"
        width: tabBox.screenGeometry.width
        height: tabBox.screenGeometry.height

        MouseArea {
            anchors.fill: parent
            onClicked: isPreview ? wrapper.close() : tabBox.model.activate(0)
        }

        PlasmaComponents3.Button {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Kirigami.Units.largeSpacing
            icon.name: "configure-symbolic"
            checkable: true
            checked: tabBox.showSettings
            onCheckedChanged: tabBox.showSettings = checked
            visible: settings.showSettingsButton && tabBox.animationFinished
        }

        Item {
            id: wnd
            anchors.centerIn: parent
            
            // Main Item Container
            FocusScope {
                id: dialogMainItem
                focus: true
                anchors.fill: parent

                readonly property var effectModeModel: ["Off", "On (always)", "On", "On (not hovered)", "On (not selected)"]
                readonly property var buttonModeModel: ["Off", "On", "On (no highlight)", "On (basic highlight)", "On (active only)"]

                Clipboard { id: clipboard }

                Timer {
                    id: mnemonicCopyTimer
                    property var item: null
                    interval: Kirigami.Units.longDuration
                    onTriggered: {
                        if (mnemonicCopyTimer.item) {
                            mnemonicCopyTimer.item.copy()
                            mnemonicCopyTimer.item = null
                        }
                        copyMenu.dismiss()
                    }
                }

                function escapeHtml(s) {
                    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
                }

                component CopyItem: MenuItem {
                    id: copyItem
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
                        clipboard.content = copyItem.value
                    }
                    onTriggered: copyItem.copy()
                    contentItem: Label {
                        text: {
                            const raw = copyItem.plainPrefix
                            const i = copyItem.mnemonicIndex
                            let head = dialogMainItem.escapeHtml(raw)
                            if (i >= 0 && i < raw.length) {
                                head = dialogMainItem.escapeHtml(raw.slice(0, i))
                                      + "<u>" + dialogMainItem.escapeHtml(raw[i]) + "</u>"
                                      + dialogMainItem.escapeHtml(raw.slice(i + 1))
                            }
                            return head + dialogMainItem.escapeHtml(copyItem.value)
                        }
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            copyItem.copy()
                            copyMenu.dismiss()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Escape) {
                            copyMenu.dismiss()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                                   || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            dialogMainItem.navigate(event.key)
                            event.accepted = true
                        } else if (copyMenu.triggerMnemonic(event.key)) {
                            event.accepted = true
                        }
                    }
                }

                Menu {
                    id: copyMenu
                    property var sourceWindow: null
                    readonly property int sourcePid: copyMenu.sourceWindow?.pid ?? 0
                    property bool sticky: false
                    onClosed: copyMenu.sourceWindow = null
                    onOpened: {
                        copyMenu.currentIndex = 0
                        copyMenu.refreshProcessInfo()
                    }
                    property int _previousIndex: 0
                    onCurrentIndexChanged: {
                        if (copyMenu.currentIndex >= 0)
                            copyMenu._previousIndex = copyMenu.currentIndex
                        else if (copyMenu.visible)
                            copyMenu.currentIndex = copyMenu._previousIndex
                    }
                    readonly property var asyncItems: [processPathItem, processCmdlineItem,
                                                       cwdItem, scopeItem, parentItem]
                    function refreshProcessInfo() {
                        for (let i = 0; i < copyMenu.asyncItems.length; ++i) {
                            const item = copyMenu.asyncItems[i]
                            item.value = "(loading...)"
                            if (item.command)
                                executableSource.connectSource(item.command)
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
                        for (let i = 0; i < copyMenu.items.length; ++i) {
                            const item = copyMenu.items[i]
                            if (item && item.mnemonicKey && item.mnemonicKey === keyCode) {
                                // Highlight first, then copy shortly after, so the
                                // selection is visible before the menu closes. KWin does
                                // not forward key releases, so this can't be done onReleased.
                                copyMenu.currentIndex = i
                                mnemonicCopyTimer.item = item
                                mnemonicCopyTimer.restart()
                                return true
                            }
                        }
                        return false
                    }
                    function dismiss() {
                        copyMenu.sticky = false
                        copyMenu.close()
                    }
                    function openAt(win, pos) {
                        copyMenu.sticky = true
                        copyMenu.sourceWindow = win
                        if (copyMenu.visible) {
                            // Already shown: just move it and refresh instead of
                            // close()+popup(), whose pending close transition would
                            // immediately hide the freshly reopened menu.
                            if (pos) {
                                copyMenu.x = pos.x
                                copyMenu.y = pos.y
                            }
                            copyMenu.refreshProcessInfo()
                        } else if (pos) {
                            copyMenu.popup(pos)
                        } else {
                            copyMenu.popup()
                        }
                    }
                    function show(win, pos) {
                        if (copyMenu.sticky) {
                            copyMenu.dismiss()
                        } else {
                            copyMenu.openAt(win, pos)
                        }
                    }

                    CopyItem {
                        id: uuidItem
                        prefix: "&UUID: "
                        value: String(copyMenu.sourceWindow?.internalId ?? "")
                    }
                    CopyItem {
                        id: pidItem
                        prefix: "PI&D: "
                        value: String(copyMenu.sourceWindow?.pid ?? "")
                    }
                    CopyItem {
                        id: processPathItem
                        prefix: "Process &Path: "
                        value: "(loading...)"
                        command: copyMenu.sourcePid
                            ? "readlink /proc/" + copyMenu.sourcePid + "/exe" : ""
                    }
                    CopyItem {
                        id: processCmdlineItem
                        prefix: "Process &Args: "
                        value: "(loading...)"
                        command: copyMenu.sourcePid
                            ? "cat /proc/" + copyMenu.sourcePid + "/cmdline | tr '\\0' ' '" : ""
                    }
                    CopyItem {
                        id: captionItem
                        prefix: "Captio&n: "
                        value: String(copyMenu.sourceWindow?.caption ?? "")
                    }
                    CopyItem {
                        id: cwdItem
                        prefix: "&CWD: "
                        value: "(loading...)"
                        command: copyMenu.sourcePid
                            ? "readlink /proc/" + copyMenu.sourcePid + "/cwd" : ""
                    }
                    CopyItem {
                        id: scopeItem
                        prefix: "Scop&e: "
                        value: "(loading...)"
                        command: copyMenu.sourcePid
                            ? "cat /proc/" + copyMenu.sourcePid + "/cgroup | head -n1 | sed 's|.*/||'" : ""
                    }
                    CopyItem {
                        id: parentItem
                        prefix: "&Launched by: "
                        value: "(loading...)"
                        command: copyMenu.sourcePid
                            ? "ps -o ppid=,comm= -p " + copyMenu.sourcePid + " | tr -s ' '" : ""
                    }
                    CopyItem {
                        id: desktopFileItem
                        prefix: "Desktop &File: "
                        value: String(copyMenu.sourceWindow?.desktopFileName ?? "")
                    }
                    CopyItem {
                        id: platformItem
                        prefix: "Platfor&m: "
                        value: {
                            const win = copyMenu.sourceWindow
                            if (!win) return ""
                            return tabBox.isX11Window(win) ? "X11/XWayland" : "Wayland"
                        }
                    }
                    CopyItem {
                        id: frameGeoItem
                        prefix: "Frame &Geometry: "
                        value: {
                            const g = copyMenu.sourceWindow?.frameGeometry
                            if (!g) return ""
                            return "x:" + g.x + " y:" + g.y + " w:" + g.width + " h:" + g.height
                        }
                    }
                    CopyItem {
                        id: outputItem
                        prefix: "&Output: "
                        value: String(copyMenu.sourceWindow?.output?.name ?? "")
                    }
                    CopyItem {
                        id: desktopsItem
                        prefix: "Des&ktops: "
                        value: {
                            const win = copyMenu.sourceWindow
                            if (!win) return ""
                            if (win.onAllDesktops) return "all"
                            return (win.desktops || []).map(d => d.name || d.id).join(", ")
                        }
                    }
                    CopyItem {
                        id: activitiesItem
                        prefix: "Acti&vities: "
                        value: {
                            const a = copyMenu.sourceWindow?.activities
                            return (a && a.length) ? a.join(", ") : "all"
                        }
                    }
                    CopyItem {
                        id: stateItem
                        prefix: "&State: "
                        value: {
                            const win = copyMenu.sourceWindow
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
                    CopyItem {
                        id: ruleItem
                        prefix: "KWin &Rule: "
                        value: {
                            const win = copyMenu.sourceWindow
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

                EditPopup {
                    id: editPopup
                    screenW: tabBox.screenGeometry.width
                    screenH: tabBox.screenGeometry.height
                }

                // Opaque backing to match original opaque look
                Rectangle {
                    anchors.fill: parent
                    // Resize slightly to avoid bleeding out of rounded corners if SVG radius is large
                    // But mostly standard radius is fine.
                    radius: 6 // common default
                    color: Kirigami.Theme.backgroundColor
                    opacity: settings.opacityBackground
                }

                // Background for the window (Using standard KSVG for themed look)
                KSvg.FrameSvgItem {
                    anchors.fill: parent
                    imagePath: "dialogs/background"
                    opacity: settings.opacityBackground
                }

                //-- Configuration Constants --
                readonly property var iconSizes: [0, Kirigami.Units.iconSizes.small, Kirigami.Units.iconSizes.smallMedium, Kirigami.Units.iconSizes.medium, Kirigami.Units.iconSizes.large, Kirigami.Units.iconSizes.huge, Kirigami.Units.iconSizes.enormous]
                readonly property int iconSize: iconSizes[settings.iconSizeIndex] ?? Kirigami.Units.iconSizes.huge
                readonly property int thumbnailWidth: Kirigami.Units.gridUnit * settings.thumbnailWidthGridUnits
                readonly property int thumbnailHeight: {
                    const input = (settings.thumbnailHeightInput || "").trim();

                    // Try aspect ratio "X:Y"
                    if (input.includes(":")) {
                        const parts = input.split(":");
                        if (parts.length === 2) {
                            const x = parseFloat(parts[0]);
                            const y = parseFloat(parts[1]);
                            if (!isNaN(x) && !isNaN(y) && x > 0) {
                                return Math.round(thumbnailWidth * (y / x));
                            }
                        }
                    }

                    // Try plain positive number (gridUnits)
                    const num = parseFloat(input);
                    if (!isNaN(num) && num > 0) {
                        return Math.round(Kirigami.Units.gridUnit * num);
                    }

                    // Default: use screen geometry ratio
                    if (tabBox.screenGeometry.height > 0) {
                        const screenFactor = tabBox.screenGeometry.width / tabBox.screenGeometry.height;
                        return Math.round(thumbnailWidth * (1.0 / screenFactor));
                    }
                    return Math.round(thumbnailWidth / 1.777); // Fallback 16:9
                }
                
                readonly property int cellMargin: Kirigami.Units.largeSpacing
                readonly property int cellWidth: thumbnailWidth + cellMargin * 2
                readonly property int cellHeight: thumbnailHeight + iconSize + cellMargin * 2

                //-- Layout Logic --
                // Calculate max dimensions
                //-- Layout Logic --
                // Calculate max dimensions
                readonly property real maxGridAspectRatioValue: tabBox.parseAspectRatio(settings.maxGridAspectRatioInput)
                property int maxW: {
                    const ratio = maxGridAspectRatioValue
                    const cap = ratio > 0 ? Math.min(ratio * maxH, tabBox.screenGeometry.width) : tabBox.screenGeometry.width
                    return cap * 0.9
                }
                property int maxH: tabBox.screenGeometry.height * 0.8
                
                // Greedy Algorithm from original Thumbnail Grid to balance rows/cols
                function columnCountRecursion(prevC, prevBestC, prevDiff) {
                    const c = prevC - 1;
                    if (c < 1) return prevBestC;

                    // don't increase vertical extent more than horizontal (keep landscape aspect)
                    // and don't exceed maxHeight
                    if (prevC * prevC <= itemCount + prevDiff ||
                            maxH < Math.ceil(itemCount / c) * cellHeight) {
                        return prevBestC;
                    }
                    const residue = itemCount % c;
                    // halts algorithm at some point
                    if (residue == 0) {
                        return c;
                    }
                    // empty slots
                    const diff = c - residue;

                    // compare it to previous count of empty slots
                    if (diff < prevDiff) {
                        return columnCountRecursion(c, c, diff);
                    } else if (diff == prevDiff) {
                        // when it's the same try again
                        return columnCountRecursion(c, prevBestC, diff);
                    }
                    // when we've found a local minimum choose this one (greedy)
                    return columnCountRecursion(c, prevBestC, diff);
                }

                property int maxGridColumnsByWidth: Math.floor(maxW / cellWidth)
                property int itemCount: repeater.total_count

                property int columns: {
                    if (itemCount === 0) return 1;
                    const c = Math.min(itemCount, maxGridColumnsByWidth);
                    if (c <= 1) return 1;
                    const residue = itemCount % c;
                    if (residue == 0) return c;
                    return columnCountRecursion(c, c, c - residue);
                }
                
                // Calculate actual content dimensions
                property int rows: Math.ceil(itemCount / Math.max(1, columns))
                
                // Ensure window has size when empty so PlaceholderMessage is visible
                // Match original behavior: defaults to 1 cell size
                property int contentWidth: itemCount === 0 ? cellWidth : columns * cellWidth
                property int contentHeight: itemCount === 0 ? cellHeight : rows * cellHeight

                // Window size tracking
                // Since we are inside Window, we bind Window's size to this logic
                Binding {
                    target: wnd
                    property: "width"
                    value: dialogMainItem.contentWidth
                }
                Binding {
                    target: wnd                        
                    property: "height"
                    value: dialogMainItem.contentHeight
                }

                //-- Navigation Logic --
                function navigate(dir) {
                    let current = tabBox.currentIndex;
                    let next = current;
                    let cols = Math.min(itemCount, columns);

                    if (dir === Qt.Key_Right) {
                        next = (current + 1) % itemCount;
                    } else if (dir === Qt.Key_Left) {
                        next = (current - 1 + itemCount) % itemCount;
                    } else if (dir === Qt.Key_Down) {
                        next = current + cols;
                        if (next >= itemCount) next = next % cols; // Wrap to top
                    } else if (dir === Qt.Key_Up) {
                        next = current - cols;
                        if (next < 0) {
                            next = itemCount - (itemCount % cols) + current; // Try bottom row
                            if (next >= itemCount) next -= cols; // Adjust if empty slot
                        }
                    }
                    
                    if (next !== current) {
                        tabBox.currentIndex = next;
                        return true;
                    }
                    return false;
                }


                // ClientModel role IDs from clientmodel.h enum
                // CaptionRole = Qt::UserRole + 1, WIdRole = Qt::UserRole + 5
                readonly property int captionRole: Qt.UserRole + 1
                readonly property int windowIdRole: Qt.UserRole + 5

                function currentWindow() {
                    const idx = tabBox.model.index(tabBox.currentIndex, 0)
                    const wid = tabBox.model.data(idx, windowIdRole)
                    return (KWin.Workspace?.stackingOrder || []).find(w => w.internalId === wid)
                }

                function currentDelegatePosition() {
                    const delegateItem = repeater.itemAt(0)?.itemAt(tabBox.currentIndex)
                    if (!delegateItem) return null
                    return delegateItem.mapToItem(dialogMainItem, 0, delegateItem.height)
                }

                function delegatePositionForWindow(win) {
                    if (!win) return null
                    const innerRep = repeater.itemAt(0)
                    if (!innerRep) return null
                    for (let i = 0; i < innerRep.count; i++) {
                        const item = innerRep.itemAt(i)
                        if (!item) continue
                        const idx = tabBox.model.index(i, 0)
                        const wid = tabBox.model.data(idx, windowIdRole)
                        const w = (KWin.Workspace?.stackingOrder || []).find(w => w.internalId === wid)
                        if (w && w.internalId === win.internalId) {
                            return item.mapToItem(dialogMainItem, 0, item.height)
                        }
                    }
                    return null
                }

                function reopenCopyMenu() {
                    if (!copyMenu.sticky) return
                    const win = currentWindow()
                    if (!win) {
                        copyMenu.dismiss()
                        return
                    }
                    copyMenu.openAt(win, currentDelegatePosition())
                }

                Timer {
                    id: reopenCopyMenuTimer
                    interval: 0
                    onTriggered: dialogMainItem.reopenCopyMenu()
                }

                function handleSpecialKeys(key) {
                    const idx = tabBox.model.index(tabBox.currentIndex, 0)
                    const window = currentWindow()

                    if (key === Qt.Key_Delete) {
                        if (tabBox.pendingIndex < 0) {
                            tabBox.pendingIndex = tabBox.currentIndex
                            tabBox.model.close(tabBox.currentIndex)
                        }
                    } else if (key === Qt.Key_PageUp) {
                        if (window) { const isMax = window.frameGeometry.width >= tabBox.screenGeometry.width - 1; window.setMaximize(!isMax, !isMax) }
                    } else if (key === Qt.Key_PageDown) {
                        if (window) window.minimized = !window.minimized;
                    } else if (key === Qt.Key_F) {
                        if (window) window.fullScreen = !window.fullScreen
                    } else if (key === Qt.Key_T) {
                        if (window) window.noBorder = !window.noBorder
                    } else if (key === Qt.Key_A) {
                        if (window) window.keepAbove = !window.keepAbove
                    } else if (key === Qt.Key_B) {
                        if (window) window.keepBelow = !window.keepBelow
                    } else if (key === Qt.Key_I) {
                        if (window) window.excludeFromCapture = !window.excludeFromCapture
                    } else if (key === Qt.Key_D) {
                        if (window) window.onAllDesktops = !window.onAllDesktops
                    } else if (key === Qt.Key_N) {
                        if (window) window.demandsAttention = !window.demandsAttention
                    } else if (key === Qt.Key_S) {
                        if (window) window.shaded = !window.shaded
                    } else if (key === Qt.Key_O) {
                        if (window) window.opacity = (window.opacity < 0.999) ? 1.0 : settings.opacityWindow
                    } else if (key === Qt.Key_1) {
                        if (window) window.skipTaskbar = !window.skipTaskbar
                    } else if (key === Qt.Key_3) {
                        if (window) window.skipPager = !window.skipPager
                    } else if (key === Qt.Key_2) {
                        if (window) window.skipSwitcher = !window.skipSwitcher
                    } else if (key === Qt.Key_P) {
                        if (window) {
                            clipboard.content = String(window.pid)
                        }
                    } else if (key === Qt.Key_Space) {
                        if (window) copyMenu.show(window, currentDelegatePosition())
                    } else if (key === Qt.Key_E) {
                        if (window) editPopup.openFor(window, currentDelegatePosition())
                    } else if (key === Qt.Key_H) {
                        if (window?.pid) {
                            // $TERMINAL overrides the terminal configured in KDE
                            // (kdeglobals [General] TerminalApplication, what KIO's
                            // KTerminalLauncherJob reads); konsole as last resort.
                            executableSource.connectSource(
                                "term=\"${TERMINAL:-$(kreadconfig6 --file kdeglobals"
                                + " --group General --key TerminalApplication 2>/dev/null)}\";"
                                + " \"${term:-konsole}\" -e htop -p " + window.pid)
                        }
                    } else if (key === Qt.Key_F12) {
                        var caption = tabBox.model.data(idx, captionRole)
                        executableSource.showDebugInfo(window, caption)
                    } else {
                        return false;
                    }
                    return true;
                }

                Keys.onPressed: (event) => {
                    if (navigate(event.key)) { event.accepted = true; return; }
                    if (handleSpecialKeys(event.key)) { event.accepted = true; return; }
                }


                Timer {
                    id: armTimer
                    interval: Kirigami.Units.veryLongDuration
                    onTriggered: tabBox.animationFinished = true
                }

                Connections {
                    target: tabBox
                    function onCurrentIndexChanged() {
                        if (copyMenu.sticky) reopenCopyMenuTimer.restart()
                    }
                    function onVisibleChanged() {
                        copyMenu.dismiss()
                        tabBox.animationFinished = false
                        console.log("[EDIT] tabBox.onVisibleChanged visible=" + tabBox.visible
                            + " editWindow.visible=" + editWindow.visible
                            + " editWindowContent.targetWindow=" + (editWindowContent.targetWindow ? editWindowContent.targetWindow.caption : "null")
                            + " editPopup.visible=" + editPopup.visible
                            + " editPopup.targetWindow=" + (editPopup.targetWindow ? editPopup.targetWindow.caption : "null"))
                        if (tabBox.visible) {
                            armTimer.start()
                            if (editWindow.visible && editWindowContent.targetWindow) {
                                const win = editWindowContent.targetWindow
                                const origGeo = editWindowContent.originalGeometry
                                const origOpacity = editWindowContent.originalOpacity
                                editWindow.close()
                                console.log("[EDIT] transferring Window→Popup for " + win.caption)
                                editPopup.openFor(win, dialogMainItem.delegatePositionForWindow(win), origGeo, origOpacity)
                            }
                        } else {
                            if (editPopup.targetWindow) {
                                const win = editPopup.targetWindow
                                const origGeo = editPopup.originalGeometry
                                const origOpacity = editPopup.originalOpacity
                                console.log("[EDIT] transferring Popup→Window for " + win.caption
                                    + " origGeo=" + JSON.stringify(origGeo)
                                    + " origOpacity=" + origOpacity)
                                editPopup.close()
                                editWindow.openFor(win, origGeo, origOpacity)
                                console.log("[EDIT] after transfer: editWindow.visible=" + editWindow.visible
                                    + " editWindowContent.targetWindow=" + (editWindowContent.targetWindow ? editWindowContent.targetWindow.caption : "null"))
                            } else {
                                console.log("[EDIT] no popup targetWindow, skipping Popup→Window transfer")
                            }
                        }
                    }
                }

                Flow {
                    id: flow
                    anchors.fill: parent
                    
                    Repeater {
                        id: repeater
                        model: tabBox.showPreview ? settings.previewRepeatCount : 1
                        readonly property int total_count: count * (repeater.itemAt(0)?.count ?? 0)

                        delegate: Repeater {
                            model: tabBox.model
                            onItemRemoved: (index, item) => {
                                if (tabBox.pendingIndex >= 0) {
                                    const restore = tabBox.pendingIndex
                                    Qt.callLater(() => {
                                        tabBox.currentIndex = Math.min(restore, tabBox.model.rowCount() - 1)
                                        tabBox.pendingIndex = -1
                                    })
                                }
                            }

                            delegate: Item {
                                width: dialogMainItem.cellWidth
                                height: dialogMainItem.cellHeight
                                
                                readonly property bool isCurrent: index === tabBox.currentIndex

                                function effectActive(mode) {
                                    if (!window || !window.minimized) return false;
                                    switch (mode) {
                                        case 0: return false;
                                        case 1: return true;
                                        case 2: return !hoverHandler.hovered && !isCurrent;
                                        case 3: return !hoverHandler.hovered;
                                        case 4: return !isCurrent;
                                        default: return false;
                                    }
                                }

                                function buttonVisible(mode, state) {
                                    switch (mode) {
                                        case 0: return false;
                                        case 1: case 3: return state || isCurrent || hoverHandler.hovered;
                                        case 2: return isCurrent || hoverHandler.hovered;
                                        case 4: return state;
                                        default: return false;
                                    }
                                }

                                function buttonHighlight(mode, state) {
                                    return (mode === 1 || mode === 4) && state;
                                }

                                readonly property var window: {
                                    const windows = KWin.Workspace?.stackingOrder || [];
                                    return windows.find(w => w.internalId === windowId) || null;
                                }

                                readonly property var maximizeArea: window ?
                                    KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window) : null

                                readonly property bool isMaximized: window ?
                                    (window.frameGeometry.width >= maximizeArea?.width - 1 && window.frameGeometry.height >= maximizeArea?.height - 1 && !window.fullScreen) : false

                                readonly property bool isX11: tabBox.isX11Window(window)

                                //-- Background/Highlight --
                                KSvg.FrameSvgItem {
                                    anchors.fill: parent
                                    imagePath: "widgets/viewitem"
                                    prefix: "hover"
                                    visible: isCurrent
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: tabBox.model.activate(index)
                                    hoverEnabled: settings.hoverSelection
                                    onPositionChanged: {
                                        if (tabBox.animationFinished)
                                            tabBox.currentIndex = index
                                    }
                                    
                                    Accessible.name: model.caption
                                    Accessible.role: Accessible.ListItem
                                }

                                //-- Content --
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: dialogMainItem.cellMargin
                                    spacing: Kirigami.Units.smallSpacing

                                    // Thumbnail Container
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        // Live Window Thumbnail
                                        KWin.WindowThumbnail {
                                            anchors.fill: parent
                                            wId: windowId
                                            opacity: effectActive(settings.minimizedThumbnailOpacity) ? settings.opacityThumbnail * 0.5 : settings.opacityThumbnail
                                            scale: effectActive(settings.minimizedThumbnailScale) ? 0.9 : 1.0
                                            rotation: effectActive(settings.minimizedThumbnailRotation) ? -2 : 0
                                            layer.enabled: effectActive(settings.minimizedBlur) || effectActive(settings.minimizedContrast)
                                            layer.effect: MultiEffect {
                                                contrast: effectActive(settings.minimizedContrast) ? -0.5 : 0.0
                                                blurEnabled: effectActive(settings.minimizedBlur)
                                                blurMax: 32
                                                blur: 1.0
                                            }
                                        }

                                        // Window Management Buttons
                                        RowLayout {
                                            anchors {
                                                left: parent.left
                                                right: parent.right
                                                top: parent.top
                                                leftMargin: -dialogMainItem.cellMargin + Kirigami.Units.smallSpacing
                                                rightMargin: -dialogMainItem.cellMargin + Kirigami.Units.smallSpacing
                                                topMargin: -dialogMainItem.cellMargin + Kirigami.Units.smallSpacing
                                            }
                                            spacing: Kirigami.Units.smallSpacing

                                            readonly property bool centerButtons: settings.centerHighlightButtons && !isCurrent && !hoverHandler.hovered

                                            Item {
                                                visible: parent.centerButtons
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 99999
                                            }

                                            // Status buttons
                                            Flow {
                                                Layout.fillHeight: true
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: parent.centerButtons ? 0 : 1
                                                Layout.minimumWidth: parent.centerButtons ? implicitWidth : 0
                                                spacing: Kirigami.Units.smallSpacing

                                                // Pin to All Desktops Button
                                                Loader {
                                                    id: buttonPin
                                                    visible: buttonVisible(settings.buttonPin, window?.onAllDesktops)
                                                    sourceComponent: buttonHighlight(settings.buttonPin, window?.onAllDesktops) ? buttonPinTrue : buttonPinFalse
                                                    readonly property string _tooltip_text: window?.onAllDesktops ? "Unpin from all desktops [D]" : "Pin to all desktops [D]"

                                                    Component {
                                                        id: buttonPinTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-pin-symbolic"
                                                            onClicked: window.onAllDesktops = !window.onAllDesktops
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonPin._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonPinFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-pin-symbolic"
                                                            onClicked: window.onAllDesktops = !window.onAllDesktops
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonPin._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Keep Below Button
                                                Loader {
                                                    id: buttonKeepBelow
                                                    visible: buttonVisible(settings.buttonKeepBelow, window?.keepBelow)
                                                    sourceComponent: buttonHighlight(settings.buttonKeepBelow, window?.keepBelow) ? buttonKeepBelowTrue : buttonKeepBelowFalse
                                                    readonly property string _tooltip_text: window?.keepBelow ? "Remove keep below [B]" : "Keep below [B]"

                                                    Component {
                                                        id: buttonKeepBelowTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-keep-below-symbolic"
                                                            onClicked: window.keepBelow = !window.keepBelow
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonKeepBelow._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonKeepBelowFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-keep-below-symbolic"
                                                            onClicked: window.keepBelow = !window.keepBelow
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonKeepBelow._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Keep Above Button
                                                Loader {
                                                    id: buttonKeepAbove
                                                    visible: buttonVisible(settings.buttonKeepAbove, window?.keepAbove)
                                                    sourceComponent: buttonHighlight(settings.buttonKeepAbove, window?.keepAbove) ? buttonKeepAboveTrue : buttonKeepAboveFalse
                                                    readonly property string _tooltip_text: window?.keepAbove ? "Remove keep above [A]" : "Keep above [A]"

                                                    Component {
                                                        id: buttonKeepAboveTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-keep-above-symbolic"
                                                            onClicked: window.keepAbove = !window.keepAbove
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonKeepAbove._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonKeepAboveFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-keep-above-symbolic"
                                                            onClicked: window.keepAbove = !window.keepAbove
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonKeepAbove._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Fullscreen Button
                                                Loader {
                                                    id: buttonFullscreen
                                                    visible: (window?.fullScreenable || false) && buttonVisible(settings.buttonFullscreen, window?.fullScreen)
                                                    sourceComponent: buttonHighlight(settings.buttonFullscreen, window?.fullScreen) ? buttonFullscreenTrue : buttonFullscreenFalse
                                                    readonly property string _tooltip_text: window?.fullScreen ? "Exit fullscreen [F]" : "Fullscreen [F]"

                                                    Component {
                                                        id: buttonFullscreenTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "view-fullscreen-symbolic"
                                                            onClicked: window.fullScreen = !window.fullScreen
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonFullscreen._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonFullscreenFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "view-fullscreen-symbolic"
                                                            onClicked: window.fullScreen = !window.fullScreen
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonFullscreen._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // No Border Button
                                                Loader {
                                                    id: buttonNoBorder
                                                    visible: buttonVisible(settings.buttonNoBorder, window?.noBorder)
                                                    sourceComponent: buttonHighlight(settings.buttonNoBorder, window?.noBorder) ? buttonNoBorderTrue : buttonNoBorderFalse
                                                    readonly property string _tooltip_text: window?.noBorder ? "Unhide titlebar & frame [T]" : "Hide titlebar & frame [T]"

                                                    Component {
                                                        id: buttonNoBorderTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-decorations-symbolic"
                                                            onClicked: window.noBorder = !window.noBorder
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonNoBorder._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonNoBorderFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-decorations-symbolic"
                                                            onClicked: window.noBorder = !window.noBorder
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonNoBorder._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Incognito Button
                                                Loader {
                                                    id: buttonIncognito
                                                    visible: buttonVisible(settings.buttonIncognito, window?.excludeFromCapture)
                                                    sourceComponent: buttonHighlight(settings.buttonIncognito, window?.excludeFromCapture) ? buttonIncognitoTrue : buttonIncognitoFalse
                                                    readonly property string _tooltip_text: window?.excludeFromCapture ? "Disable hide from capture [I]" : "Hide from screenshots/recordings [I]"

                                                    Component {
                                                        id: buttonIncognitoTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "view-private-symbolic"
                                                            onClicked: window.excludeFromCapture = !window.excludeFromCapture
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonIncognito._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonIncognitoFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "view-private-symbolic"
                                                            onClicked: window.excludeFromCapture = !window.excludeFromCapture
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonIncognito._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Demands Attention Button
                                                Loader {
                                                    id: buttonDemandsAttention
                                                    visible: buttonVisible(settings.buttonDemandsAttention, window?.demandsAttention)
                                                    sourceComponent: buttonHighlight(settings.buttonDemandsAttention, window?.demandsAttention) ? buttonDemandsAttentionTrue : buttonDemandsAttentionFalse
                                                    readonly property string _tooltip_text: window?.demandsAttention ? "Remove attention demand [N]" : "Demand attention [N]"

                                                    Component {
                                                        id: buttonDemandsAttentionTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "notifications-symbolic"
                                                            onClicked: window.demandsAttention = !window.demandsAttention
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonDemandsAttention._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }

                                                            SequentialAnimation on opacity {
                                                                loops: Animation.Infinite
                                                                running: true
                                                                NumberAnimation { to: 1.0; duration: 200 }
                                                                NumberAnimation { to: 0.2; duration: 200 }
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonDemandsAttentionFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "notifications-symbolic"
                                                            onClicked: window.demandsAttention = !window.demandsAttention
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonDemandsAttention._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Shaded Button
                                                Loader {
                                                    id: buttonShaded
                                                    visible: (window?.shadeable || false) && buttonVisible(settings.buttonShaded, window?.shaded)
                                                    sourceComponent: buttonHighlight(settings.buttonShaded, window?.shaded) ? buttonShadedTrue : buttonShadedFalse
                                                    readonly property string _tooltip_text: window?.shaded ? "Unshade [S]" : "Shade [S]"

                                                    Component {
                                                        id: buttonShadedTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-shade-symbolic"
                                                            onClicked: window.shaded = !window.shaded
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonShaded._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonShadedFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-shade-symbolic"
                                                            onClicked: window.shaded = !window.shaded
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonShaded._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Opacity Toggle Button
                                                Loader {
                                                    id: buttonTransparency
                                                    readonly property bool isTransparent: window ? (window.opacity < 1) : false
                                                    visible: buttonVisible(settings.buttonTransparency, isTransparent)
                                                    sourceComponent: buttonHighlight(settings.buttonTransparency, isTransparent) ? buttonTransparencyTrue : buttonTransparencyFalse
                                                    readonly property string _tooltip_text: isTransparent ? "Make opaque [O]" : "Make transparent [O]"

                                                    Component {
                                                        id: buttonTransparencyTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "edit-opacity-symbolic"
                                                            onClicked: window.opacity = isTransparent ? 1.0 : settings.opacityWindow
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonTransparency._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonTransparencyFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "edit-opacity-symbolic"
                                                            onClicked: window.opacity = isTransparent ? 1.0 : settings.opacityWindow
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonTransparency._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Skip Taskbar Button
                                                Loader {
                                                    id: buttonSkipTaskbar
                                                    visible: buttonVisible(settings.buttonSkipTaskbar, window?.skipTaskbar)
                                                    sourceComponent: buttonHighlight(settings.buttonSkipTaskbar, window?.skipTaskbar) ? buttonSkipTaskbarTrue : buttonSkipTaskbarFalse
                                                    readonly property string _tooltip_text: window?.skipTaskbar ? "Show in taskbar [1]" : "Skip taskbar [1]"

                                                    Component {
                                                        id: buttonSkipTaskbarTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "view-tasks-all-symbolic"
                                                            onClicked: window.skipTaskbar = !window.skipTaskbar
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipTaskbar._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonSkipTaskbarFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "view-tasks-all-symbolic"
                                                            onClicked: window.skipTaskbar = !window.skipTaskbar
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipTaskbar._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                 // Skip Switcher Button
                                                Loader {
                                                    id: buttonSkipSwitcher
                                                    visible: buttonVisible(settings.buttonSkipSwitcher, window?.skipSwitcher)
                                                    sourceComponent: buttonHighlight(settings.buttonSkipSwitcher, window?.skipSwitcher) ? buttonSkipSwitcherTrue : buttonSkipSwitcherFalse
                                                    readonly property string _tooltip_text: window?.skipSwitcher ? "Show in switcher [2]" : "Skip switcher [2]"

                                                    Component {
                                                        id: buttonSkipSwitcherTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-list"
                                                            onClicked: window.skipSwitcher = !window.skipSwitcher
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipSwitcher._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonSkipSwitcherFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-list"
                                                            onClicked: window.skipSwitcher = !window.skipSwitcher
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipSwitcher._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Skip Pager Button
                                                Loader {
                                                    id: buttonSkipPager
                                                    visible: buttonVisible(settings.buttonSkipPager, window?.skipPager)
                                                    sourceComponent: buttonHighlight(settings.buttonSkipPager, window?.skipPager) ? buttonSkipPagerTrue : buttonSkipPagerFalse
                                                    readonly property string _tooltip_text: window?.skipPager ? "Show in pager [3]" : "Skip pager [3]"

                                                    Component {
                                                        id: buttonSkipPagerTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: "window-duplicate-symbolic"
                                                            onClicked: window.skipPager = !window.skipPager
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipPager._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonSkipPagerFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: "window-duplicate-symbolic"
                                                            onClicked: window.skipPager = !window.skipPager
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonSkipPager._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }
                                            }

                                            // Action buttons
                                            Flow {
                                                Layout.alignment: Qt.AlignRight
                                                Layout.fillHeight: true
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: parent.centerButtons ? 0 : 1
                                                Layout.minimumWidth: parent.centerButtons ? implicitWidth : 0
                                                spacing: Kirigami.Units.smallSpacing
                                                layoutDirection: Qt.RightToLeft

                                                // Close Button
                                                PlasmaComponents3.Button {
                                                    id: buttonClose
                                                    visible: settings.buttonClose && model.closeable && (isCurrent || hoverHandler.hovered || buttonClose.hovered)
                                                    icon.name: "window-close-symbolic"
                                                    onClicked: {
                                                        tabBox.pendingIndex = tabBox.currentIndex
                                                        tabBox.model.close(index)
                                                    }
                                                    background.opacity: settings.opacityWindowButton
                                                    implicitWidth: buttonSize
                                                    implicitHeight: buttonSize
                                                    ToolTip.text: "Close [Del]"
                                                    ToolTip.visible: hovered
                                                }

                                                // Maximize/Restore Button
                                                Loader {
                                                    id: buttonMaximize
                                                    visible: (window?.maximizable || false) && buttonVisible(settings.buttonMaximize, isMaximized)
                                                    sourceComponent: buttonHighlight(settings.buttonMaximize, isMaximized) ? buttonMaximizeTrue : buttonMaximizeFalse
                                                    readonly property string _tooltip_text: isMaximized ? "Unmaximize [PgUp]" : "Maximize [PgUp]"

                                                    Component {
                                                        id: buttonMaximizeTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: (isMaximized && hovered) ? "window-restore-symbolic" : "window-maximize-symbolic"
                                                            onClicked: if (window) {
                                                                window.setMaximize(!isMaximized, !isMaximized)
                                                            }
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonMaximize._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: buttonMaximizeFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: (isMaximized && hovered) ? "window-restore-symbolic" : "window-maximize-symbolic"
                                                            onClicked: if (window) {
                                                                window.setMaximize(!isMaximized, !isMaximized)
                                                            }
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: buttonMaximize._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Minimize/Restore Button
                                                Loader {
                                                    id: minRestoreButton
                                                    visible: (window?.minimizable || false) && buttonVisible(settings.buttonMinimize, window?.minimized)
                                                    sourceComponent: buttonHighlight(settings.buttonMinimize, window?.minimized) ? minRestoreTrue : minRestoreFalse
                                                    readonly property string _tooltip_text: window?.minimized ? "Unminimize [PgDn]" : "Minimize [PgDn]"

                                                    Component {
                                                        id: minRestoreTrue
                                                        PlasmaComponents3.RoundButton {
                                                            icon.name: (window?.minimized && hovered) ? "window-restore-symbolic" : "window-minimize-symbolic"
                                                            onClicked: window.minimized = !window.minimized
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: minRestoreButton._tooltip_text
                                                            ToolTip.visible: hovered
                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true
                                                                shadowColor: Kirigami.Theme.neutralTextColor
                                                                shadowBlur: 0.5
                                                            }
                                                        }
                                                    }

                                                    Component {
                                                        id: minRestoreFalse
                                                        PlasmaComponents3.Button {
                                                            icon.name: (window?.minimized && hovered) ? "window-restore-symbolic" : "window-minimize-symbolic"
                                                            onClicked: window.minimized = !window.minimized
                                                            background.opacity: settings.opacityWindowButton
                                                            implicitWidth: buttonSize
                                                            implicitHeight: buttonSize
                                                            ToolTip.text: minRestoreButton._tooltip_text
                                                            ToolTip.visible: hovered
                                                        }
                                                    }
                                                }

                                                // Debug Button
                                                PlasmaComponents3.Button {
                                                    id: buttonDebug
                                                    visible: settings.buttonDebug && (isCurrent || hoverHandler.hovered || buttonDebug.hovered)
                                                    icon.name: "info-symbolic"
                                                    onClicked: executableSource.showDebugInfo(window, model.caption)
                                                    background.opacity: settings.opacityWindowButton
                                                    implicitWidth: buttonSize
                                                    implicitHeight: buttonSize
                                                    ToolTip.text: "Show window debug info [F12]"
                                                    ToolTip.visible: hovered
                                                }
                                            }

                                            Item {
                                                visible: parent.centerButtons
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 99999
                                            }
                                        }

                                        HoverHandler {
                                            id: hoverHandler
                                        }

                                        // Application Icon Overlay
                                        Kirigami.Icon {
                                            id: appIcon
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: -height/2 
                                            width: dialogMainItem.iconSize
                                            height: width
                                            source: model.icon
                                            opacity: effectActive(settings.minimizedIconOpacity) ? settings.opacityThumbnail * 0.5 : settings.opacityThumbnail
                                        }

                                        // Minimized indicator icon
                                        Kirigami.Icon {
                                            visible: effectActive(settings.minimizedIcon)
                                            anchors.right: appIcon.left
                                            anchors.rightMargin: Kirigami.Units.largeSpacing
                                            anchors.bottom: appIcon.bottom
                                            width: Math.max(Kirigami.Units.iconSizes.small, dialogMainItem.iconSize / 2)
                                            height: width
                                            source: "window-minimize-symbolic"
                                            opacity: settings.opacityThumbnail
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                shadowEnabled: true
                                                shadowColor: Qt.rgba(0, 0, 0, 0.6)
                                                shadowBlur: 0.5
                                                shadowVerticalOffset: 2
                                                shadowHorizontalOffset: 0
                                            }
                                        }

                                        // Windowing protocol badge, right of the icon
                                        Loader {
                                            active: settings.showProtocol
                                            visible: active
                                            anchors.left: appIcon.right
                                            anchors.leftMargin: -Kirigami.Units.smallSpacing - width * 3 / 7
                                            anchors.bottom: appIcon.bottom
                                            sourceComponent: isX11 ? x11Badge : waylandBadge
                                        }

                                        Component {
                                            id: waylandBadge
                                            Kirigami.Icon {
                                                source: "wayland"
                                                fallback: "preferences-desktop-display"
                                                width: Math.max(Kirigami.Units.iconSizes.small,
                                                                dialogMainItem.iconSize / 2)
                                                height: width
                                                opacity: settings.opacityThumbnail
                                            }
                                        }

                                        Component {
                                            id: x11Badge
                                            Kirigami.Icon {
                                                source: "xorg"
                                                fallback: "preferences-desktop-display"
                                                width: Math.max(Kirigami.Units.iconSizes.small,
                                                                dialogMainItem.iconSize / 2)
                                                height: width
                                                opacity: settings.opacityThumbnail
                                            }
                                        }
                                    }

                                    // Spacing for the overlapping icon
                                    Item { 
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: dialogMainItem.iconSize/2 
                                    }

                                    // Caption
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: model.caption
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideMiddle
                                        maximumLineCount: 1
                                        font.weight: isCurrent ? Font.Bold : Font.Normal
                                        font.italic: effectActive(settings.minimizedItalics)
                                        font.strikeout: effectActive(settings.minimizedStrikethrough)
                                        font.underline: effectActive(settings.minimizedUnderline)
                                        // color: "white" // Removed to use theme default
                                    }
                                }
                            }
                        }
                    }
                } // Flow

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.largeSpacing * 2
                    icon.source: "edit-none"
                    text: "No open windows"
                    visible: repeater.total_count === 0
                }
            }
        }

        FocusScope {
            id: settingsWnd
            visible: tabBox.showPreview

            y: 0
            anchors.horizontalCenter: parent.horizontalCenter
            width: settingsItem.implicitWidth
            height: settingsItem.implicitHeight

            Item {
                id: settingsItem
                implicitWidth: Kirigami.Units.gridUnit * 40
                implicitHeight: settingsContent.implicitHeight + Kirigami.Units.largeSpacing * 2

                Rectangle {
                    anchors.fill: parent
                    color: Kirigami.Theme.backgroundColor
                }

                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: settingsContent
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: "NB: Restart KWin (log out and log in again) to apply settings to the real task switcher."
                        font.bold: true
                        visible: tabBox.isPreview
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            text: "Config file:"
                            font.italic: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }
                        PlasmaComponents3.TextField {
                            text: settings.location
                            font.family: "monospace"
                            font.italic: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                            readOnly: true
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.TextField {
                            text: settings.category
                            font.family: "monospace"
                            font.italic: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                            readOnly: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Preview repeat count:"; font.italic: true }
                        PlasmaComponents3.Slider {
                            from: 1
                            to: 30
                            value: settings.previewRepeatCount
                            stepSize: 1
                            onMoved: settings.previewRepeatCount = Math.round(value)
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: settings.previewRepeatCount
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.CheckBox {
                            id: cbHoverSelection
                            checked: settings.hoverSelection
                            onCheckedChanged: settings.hoverSelection = checked
                        }
                        PlasmaComponents3.Label {
                            textFormat: Text.RichText
                            text: "Select with mouse hover<sup>?</sup>"
                            ToolTip {
                                text: "Useful when \"Show selected windows\" (in Task Switcher - System Setting) is enabled, " +
                                      "to preview a window by just hovering on it in the grid (with the mouse cursor). \n\n" + 
                                      "Note: regardless of this setting, you can always: \n" +
                                      "- Click on a window to switch to it. \n" +
                                      "- Cancel task switching by clicking outside the grid or by pressing [Esc] on the keyboard."
                                visible: ma3.containsMouse
                                delay: 0
                                width: 480
                            }
                            MouseArea { id: ma3; anchors.fill: parent; hoverEnabled: true; onClicked: cbHoverSelection.toggle() }
                        }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents3.CheckBox {
                            id: cbShowProtocol
                            checked: settings.showProtocol
                            onCheckedChanged: settings.showProtocol = checked
                        }
                        PlasmaComponents3.Label {
                            textFormat: Text.RichText
                            text: "Show windowing protocol<sup>?</sup>"
                            ToolTip.text: "Display the windowing protocol (Wayland or X11) next to each window's icon."
                            ToolTip.visible: ma4.containsMouse
                            MouseArea { id: ma4; anchors.fill: parent; hoverEnabled: true; onClicked: cbShowProtocol.toggle() }
                        }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents3.CheckBox {
                            id: cbButtonSettings
                            checked: settings.showSettingsButton
                            onCheckedChanged: settings.showSettingsButton = checked
                        }
                        PlasmaComponents3.Label {
                            textFormat: Text.RichText
                            text: "Settings button<sup>?</sup>"
                            ToolTip.text: "Show a settings button (at the bottom left of the screen), when the task switcher is opened."
                            ToolTip.visible: ma5.containsMouse
                            MouseArea { id: ma5; anchors.fill: parent; hoverEnabled: true; onClicked: cbButtonSettings.toggle() }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            textFormat: Text.RichText
                            text: "Max grid aspect ratio<sup>?</sup>"
                            ToolTip {
                                text: "Limits how wide the grid of windows can be relative to its height. \n" +
                                      "Useful for ultrawide displays, to prevent the task switcher from becoming too wide. \n\n" +
                                      "E.g. 21:9 means that: \n" +
                                      "- on monitors wider than 21:9, the grid will stay within a central 21:9 rectangle, \n" +
                                      "- on monitors narrower than 21:9, the limit is the width of the monitor. \n\n" +
                                      "Set to 0 for no limit (always uses the width of the monitor as the limit). \n\n" + 
                                      "Note: you can test the effect of this setting by increasing \"Preview repeat count\"."
                                visible: ma1.containsMouse
                                delay: 0
                                width: 480
                            }
                            MouseArea { id: ma1; anchors.fill: parent; hoverEnabled: true; }
                        }
                        PlasmaComponents3.Slider {
                            id: maxAspectRatioSlider
                            from: 0.0
                            to: 5.0
                            stepSize: 0.01
                            value: Math.max(0, Math.min(5, dialogMainItem.maxGridAspectRatioValue))
                            onMoved: settings.maxGridAspectRatioInput = tabBox.toFractionString(value)
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.TextField {
                            text: settings.maxGridAspectRatioInput
                            onTextEdited: settings.maxGridAspectRatioInput = text
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            id: minimizedWindowsLabel
                            textFormat: Text.RichText
                            text: "Minimized<sup>?</sup><br>windows"
                            ToolTip.text: "Change the appearance of windows that are minimized."
                            ToolTip.visible: ma2.containsMouse
                            MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; }
                        }

                        ToolSeparator { Layout.fillHeight: true }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label {
                                    text: "Indicator<sup>?</sup>"
                                    textFormat: Text.RichText
                                    ToolTip.text: "Show a \"minimized\" icon to the left of the app icon, if the window is minimized."
                                    ToolTip.visible: maIndicator.containsMouse
                                    MouseArea { id: maIndicator; anchors.fill: parent; hoverEnabled: true; }
                                }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedIcon
                                    onActivated: settings.minimizedIcon = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label {
                                    text: "Icon opacity<sup>?</sup>"
                                    textFormat: Text.RichText
                                    ToolTip.text: "Reduce app icon opacity, if the window is minimized."
                                    ToolTip.visible: maIconOpacity.containsMouse
                                    MouseArea { id: maIconOpacity; anchors.fill: parent; hoverEnabled: true; }
                                }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedIconOpacity
                                    onActivated: settings.minimizedIconOpacity = currentIndex
                                }
                            }
                            
                            PlasmaComponents3.GroupBox {
                                PlasmaComponents3.Label { text: "Text:"; Layout.fillHeight: true; }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Italics" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedItalics
                                    onActivated: settings.minimizedItalics = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Strikethrough" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedStrikethrough
                                    onActivated: settings.minimizedStrikethrough = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Underline" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedUnderline
                                    onActivated: settings.minimizedUnderline = currentIndex
                                }
                            }

                            PlasmaComponents3.GroupBox {
                                PlasmaComponents3.Label { text: "Thumbnail:" }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Contrast" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedContrast
                                    onActivated: settings.minimizedContrast = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Opacity" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedThumbnailOpacity
                                    onActivated: settings.minimizedThumbnailOpacity = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Scale" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedThumbnailScale
                                    onActivated: settings.minimizedThumbnailScale = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Rotation" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedThumbnailRotation
                                    onActivated: settings.minimizedThumbnailRotation = currentIndex
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                PlasmaComponents3.Label { text: "Blur" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.effectModeModel
                                    currentIndex: settings.minimizedBlur
                                    onActivated: settings.minimizedBlur = currentIndex
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Thumbnail width:" }
                        PlasmaComponents3.SpinBox {
                            from: 8
                            to: 32
                            value: settings.thumbnailWidthGridUnits
                            onValueModified: settings.thumbnailWidthGridUnits = value
                        }
                        PlasmaComponents3.Label { text: "grid units" }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents3.Label { text: "Icon size:" }
                        PlasmaComponents3.ComboBox {
                            model: ["None", "Small", "Small-Medium", "Medium", "Large", "Huge", "Enormous"]
                            currentIndex: settings.iconSizeIndex
                            onActivated: settings.iconSizeIndex = currentIndex
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Thumbnail height:" }
                        PlasmaComponents3.TextField {
                            text: settings.thumbnailHeightInput
                            onTextEdited: settings.thumbnailHeightInput = text
                        }
                        PlasmaComponents3.Label {
                            text: "e.g. 9 (grid units), 16:9 (aspect ratio), or blank for screen ratio"
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Thumbnail opacity:" }
                        PlasmaComponents3.Slider {
                            from: 0.0
                            to: 1.0
                            value: settings.opacityThumbnail
                            stepSize: 0.01
                            onMoved: settings.opacityThumbnail = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.opacityThumbnail * 100) + "%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Background opacity:" }
                        PlasmaComponents3.Slider {
                            from: 0.0
                            to: 1.0
                            value: settings.opacityBackground
                            stepSize: 0.01
                            onMoved: settings.opacityBackground = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.opacityBackground * 100) + "%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Window button opacity:" }
                        PlasmaComponents3.Slider {
                            from: 0.0
                            to: 1.0
                            value: settings.opacityWindowButton
                            stepSize: 0.01
                            onMoved: settings.opacityWindowButton = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.opacityWindowButton * 100) + "%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Window button size:" }
                        PlasmaComponents3.Slider {
                            from: 0.5
                            to: 4.0
                            value: settings.buttonSize
                            stepSize: 0.1
                            onMoved: settings.buttonSize = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: settings.buttonSize.toFixed(1) + "× grid unit"
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            id: windowButtonsLabel
                            textFormat: Text.RichText
                            text: "Window<sup>?</sup><br>buttons"
                            ToolTip.text: "Configure the visibility of window management buttons on each thumbnail.\n\n" +
                                          "Each button can be set to one of the following modes:\n" +
                                          "- Off: the button is never shown.\n" +
                                          "- On: the button is shown when hovered/selected or when its state is active, and highlighted (round, with shadow) when active.\n" +
                                          "- On (no highlight): the button is shown when hovered/selected (no highlight).\n" +
                                          "- On (basic highlight): the button is shown when hovered/selected or when its state is active, but never uses the round highlighted style.\n" +
                                          "- On (active only): the button is only shown when its state is active, and highlighted (round, with shadow)."
                            ToolTip.visible: maWindowButtons.containsMouse
                            MouseArea { id: maWindowButtons; anchors.fill: parent; hoverEnabled: true; }
                        }

                        ToolSeparator { Layout.fillHeight: true }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.largeSpacing

                            RowLayout {
                                PlasmaComponents3.Label {
                                    text: "Center highlight buttons<sup>?</sup>"
                                    textFormat: Text.RichText
                                    ToolTip.text: "When not hovered/selected, move status buttons (normally on the left) and action buttons (normally on the right) towards the center of the thumbnail."
                                    ToolTip.visible: maInvertButtons.containsMouse
                                    MouseArea { id: maInvertButtons; anchors.fill: parent; hoverEnabled: true; onClicked: cbInvertButtons.toggle() }
                                }
                                PlasmaComponents3.CheckBox {
                                    id: cbInvertButtons
                                    checked: settings.centerHighlightButtons
                                    onCheckedChanged: settings.centerHighlightButtons = checked
                                }
                            }

                            PlasmaComponents3.GroupBox {
                                PlasmaComponents3.Label { text: "Left:" }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Pin" }
                            PlasmaComponents3.ComboBox {
                                model: dialogMainItem.buttonModeModel
                                currentIndex: settings.buttonPin
                                onActivated: settings.buttonPin = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Keep below" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonKeepBelow
                                    onActivated: settings.buttonKeepBelow = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Keep above" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonKeepAbove
                                    onActivated: settings.buttonKeepAbove = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Fullscreen" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonFullscreen
                                    onActivated: settings.buttonFullscreen = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "No titlebar" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonNoBorder
                                    onActivated: settings.buttonNoBorder = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Incognito" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonIncognito
                                    onActivated: settings.buttonIncognito = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Demands attention" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonDemandsAttention
                                    onActivated: settings.buttonDemandsAttention = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Shaded" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonShaded
                                    onActivated: settings.buttonShaded = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Transparency" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonTransparency
                                    onActivated: settings.buttonTransparency = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Skip taskbar" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonSkipTaskbar
                                    onActivated: settings.buttonSkipTaskbar = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Skip switcher" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonSkipSwitcher
                                    onActivated: settings.buttonSkipSwitcher = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Skip pager" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonSkipPager
                                    onActivated: settings.buttonSkipPager = currentIndex
                                }
                            }

                            PlasmaComponents3.GroupBox {
                                PlasmaComponents3.Label { text: "Right:" }
                            }
                            RowLayout {
                                PlasmaComponents3.Label {
                                    text: "Debug"
                                    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: cbDebug.toggle() }
                                }
                                PlasmaComponents3.CheckBox {
                                    id: cbDebug
                                    checked: settings.buttonDebug
                                    onCheckedChanged: settings.buttonDebug = checked
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Minimize" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonMinimize
                                    onActivated: settings.buttonMinimize = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label { text: "Maximize" }
                                PlasmaComponents3.ComboBox {
                                    model: dialogMainItem.buttonModeModel
                                    currentIndex: settings.buttonMaximize
                                    onActivated: settings.buttonMaximize = currentIndex
                                }
                            }
                            RowLayout {
                                PlasmaComponents3.Label {
                                    text: "Close"
                                    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: cbClose.toggle() }
                                }
                                PlasmaComponents3.CheckBox {
                                    id: cbClose
                                    checked: settings.buttonClose
                                    onCheckedChanged: settings.buttonClose = checked
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: settings.buttonTransparency != 0
                        PlasmaComponents3.Label { text: "Window transparency button opacity:" }
                        PlasmaComponents3.Slider {
                            from: 0.01
                            to: 0.99
                            value: settings.opacityWindow
                            stepSize: 0.01
                            onMoved: settings.opacityWindow = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.opacityWindow * 100) + "%"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []
        // Replies are routed by matching sourceName against each item's current
        // `command` binding, so there is no long-lived request map to mutate.
        onNewData: (sourceName, data) => {
            const result = String(data.stdout).trim()
            for (let i = 0; i < copyMenu.asyncItems.length; ++i) {
                const item = copyMenu.asyncItems[i]
                if (item.command === sourceName)
                    item.value = result
            }
            executableSource.disconnectSource(sourceName)
        }

        function showDebugInfo(window, caption) {
            var text = dumpProperties(window)
            var cmd = "echo '" + text.replace(/'/g, "'\\''") + "' > /tmp/kwin_debug_window.txt && kdialog --textbox /tmp/kwin_debug_window.txt --title 'KWin: " + caption + "' --geometry 480x600"
            executableSource.connectSource(cmd)
        }
    }

    Window {
        id: editWindow
        visible: false
        flags: Qt.Window | Qt.WindowStaysOnTopHint
        color: Kirigami.Theme.backgroundColor
        width: Kirigami.Units.gridUnit * 32
        height: Kirigami.Units.gridUnit * 18

        function openFor(win, origGeo, origOpacity) {
            editWindowContent.targetWindow = null
            editWindowContent.openFor(win, null, origGeo, origOpacity)
            editWindow.show()
        }

        title: editWindowContent.targetWindow ? ("Edit: " + editWindowContent.targetWindow.caption) : "Edit Window Geometry"

        EditPopup {
            id: editWindowContent
            closePolicy: Popup.NoAutoClose
            x: 0
            y: 0
            width: parent.width
            height: parent.height
            screenW: tabBox.screenGeometry.width
            screenH: tabBox.screenGeometry.height
            onClosed: editWindow.close()
            background: null
        }
    }
}
