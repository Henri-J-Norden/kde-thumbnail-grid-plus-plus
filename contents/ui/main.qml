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
        property bool showSettingsButton: true
        property bool showProtocol: true
        property bool lockGridWidth: true
        property bool centerHighlightButtons: true

        property int thumbnailWidthGridUnits: 16
        property string thumbnailHeightInput: "16:10"
        property string maxGridAspectRatioInput: "21:9"
        
        property int previewRepeatCount: 1
        property real buttonSize: 1.6

        property real opacityBackground: 0.5
        property real opacityThumbnail: 1.0
        property real opacityWindowButton: 0.75
        property real opacityWindow: 0.7

        property int iconSizeIndex: 4

        // Indices into effectModeModel
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

        // Indices into buttonModeModel.
        property int buttonMaximize: 2
        property int buttonMaximizeHorizontal: 0
        property int buttonMaximizeVertical: 0
        property int buttonFullscreen: 1
        property int buttonNoBorder: 1
        property int buttonMinimize: 2
        property int buttonPin: 1
        property int buttonKeepAbove: 1
        property int buttonKeepBelow: 5
        property int buttonIncognito: 5
        property int buttonDemandsAttention: 5
        property int buttonShaded: 5  // Broken on wayland https://bugs.kde.org/show_bug.cgi?id=377162
        property int buttonTransparency: 5
        property int buttonSkipTaskbar: 5
        property int buttonSkipPager: 5
        property int buttonSkipSwitcher: 5

        property bool buttonClose: true
        property bool buttonDebug: false
    }

    // Labels for the mode settings above. Deliberately not declared inside Settings:
    // it would serialise them into the config file as if they were user values.
    // The index is what gets stored, so these lists must not be reordered without
    // remapping the saved values and WindowButton's mode switches.
    readonly property var effectModeModel: ["0 Off",
                                            "1 On (always)",
                                            "2 On",
                                            "3 On (not hovered)",
                                            "4 On (not selected)"]
    // "button" = flat style, "badge" = round with a shadow.
    readonly property var buttonModeModel: ["0 Off",
                                            "1 Button on hover, badge when active",
                                            "2 Button on hover, badge when active & hovered",
                                            "3 Button on hover + when active",
                                            "4 Button on hover",
                                            "5 Badge when active only"]

    // Buttons with no window state to reflect (close, debug) have a plain on/off
    // setting; these map it onto buttonModeModel.
    readonly property int buttonModeOff: 0
    readonly property int buttonModeOnHover: 4

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

        onVisibleChanged: {
            dialogMainItem.lockedColumns = 0
            // Latch after the model has populated for this invocation.
            if (visible && settings.lockGridWidth)
                Qt.callLater(() => dialogMainItem.lockedColumns = dialogMainItem.columns)
        }
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

                // Latched on open so the grid doesn't reflow horizontally when
                // windows are closed mid-session. 0 = not latched yet.
                property int lockedColumns: 0

                // Fewest columns that keep itemCount rows within maxH.
                readonly property int minColumnsByHeight: {
                    const rowsThatFit = Math.floor(maxH / cellHeight);
                    if (itemCount === 0 || rowsThatFit < 1) return 1;
                    return Math.ceil(itemCount / rowsThatFit);
                }

                property int columns: {
                    if (settings.lockGridWidth && lockedColumns > 0) {
                        // Relax the lock, upward only, if the grid would overflow
                        // vertically (e.g. windows opened while the switcher is up).
                        return Math.min(Math.max(lockedColumns, minColumnsByHeight),
                                        Math.max(1, maxGridColumnsByWidth));
                    }
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
                    } else if (key === Qt.Key_Home) {
                        if (window) { const area = KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window); const isV = window.frameGeometry.height >= area?.height - 1; const isH = window.frameGeometry.width >= area?.width - 1; window.setMaximize(!isV, isH) }
                    } else if (key === Qt.Key_End) {
                        if (window) { const area = KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window); const isV = window.frameGeometry.height >= area?.height - 1; const isH = window.frameGeometry.width >= area?.width - 1; window.setMaximize(isV, !isH) }
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
                        if (tabBox.visible) {
                            armTimer.start()
                            if (editWindow.visible && editWindowContent.targetWindow) {
                                const win = editWindowContent.targetWindow
                                const origGeo = editWindowContent.originalGeometry
                                const origOpacity = editWindowContent.originalOpacity
                                editWindow.close()
                                editPopup.openFor(win, dialogMainItem.delegatePositionForWindow(win), origGeo, origOpacity)
                            }
                        } else {
                            if (editPopup.targetWindow) {
                                const win = editPopup.targetWindow
                                const origGeo = editPopup.originalGeometry
                                const origOpacity = editPopup.originalOpacity
                                editPopup.close()
                                editWindow.openFor(win, origGeo, origOpacity)
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
                                id: cell
                                width: dialogMainItem.cellWidth
                                height: dialogMainItem.cellHeight

                                readonly property bool isCurrent: index === tabBox.currentIndex

                                // Context consumed by the WindowButton instances below.
                                readonly property bool hovered: hoverHandler.hovered
                                readonly property real buttonSize: tabBox.buttonSize
                                readonly property real buttonBackgroundOpacity: settings.opacityWindowButton

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

                                readonly property var window: {
                                    const windows = KWin.Workspace?.stackingOrder || [];
                                    return windows.find(w => w.internalId === windowId) || null;
                                }

                                readonly property var maximizeArea: window ?
                                    KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window) : null

                                readonly property bool isMaximizedHorizontal: window ?
                                    (window.frameGeometry.width >= maximizeArea?.width - 1 && !window.fullScreen) : false

                                readonly property bool isMaximizedVertical: window ?
                                    (window.frameGeometry.height >= maximizeArea?.height - 1 && !window.fullScreen) : false

                                readonly property bool isMaximized: isMaximizedHorizontal && isMaximizedVertical

                                readonly property bool isTransparent: window ? (window.opacity < 1) : false

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
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonPin
                                                    checked: window?.onAllDesktops ?? false
                                                    iconName: "window-pin-symbolic"
                                                    tooltipChecked: "Unpin from all desktops [D]"
                                                    tooltipUnchecked: "Pin to all desktops [D]"
                                                    onToggled: window.onAllDesktops = !window.onAllDesktops
                                                }

                                                // Keep Below Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonKeepBelow
                                                    checked: window?.keepBelow ?? false
                                                    iconName: "window-keep-below-symbolic"
                                                    tooltipChecked: "Remove keep below [B]"
                                                    tooltipUnchecked: "Keep below [B]"
                                                    onToggled: window.keepBelow = !window.keepBelow
                                                }

                                                // Keep Above Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonKeepAbove
                                                    checked: window?.keepAbove ?? false
                                                    iconName: "window-keep-above-symbolic"
                                                    tooltipChecked: "Remove keep above [A]"
                                                    tooltipUnchecked: "Keep above [A]"
                                                    onToggled: window.keepAbove = !window.keepAbove
                                                }

                                                // Fullscreen Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonFullscreen
                                                    checked: window?.fullScreen ?? false
                                                    supported: window?.fullScreenable ?? false
                                                    iconName: "view-fullscreen-symbolic"
                                                    tooltipChecked: "Exit fullscreen [F]"
                                                    tooltipUnchecked: "Fullscreen [F]"
                                                    onToggled: window.fullScreen = !window.fullScreen
                                                }

                                                // No Border Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonNoBorder
                                                    checked: window?.noBorder ?? false
                                                    iconName: "window-decorations-symbolic"
                                                    tooltipChecked: "Unhide titlebar & frame [T]"
                                                    tooltipUnchecked: "Hide titlebar & frame [T]"
                                                    onToggled: window.noBorder = !window.noBorder
                                                }

                                                // Incognito Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonIncognito
                                                    checked: window?.excludeFromCapture ?? false
                                                    iconName: "view-private-symbolic"
                                                    tooltipChecked: "Disable hide from capture [I]"
                                                    tooltipUnchecked: "Hide from screenshots/recordings [I]"
                                                    onToggled: window.excludeFromCapture = !window.excludeFromCapture
                                                }

                                                // Demands Attention Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonDemandsAttention
                                                    checked: window?.demandsAttention ?? false
                                                    blink: true
                                                    iconName: "notifications-symbolic"
                                                    tooltipChecked: "Remove attention demand [N]"
                                                    tooltipUnchecked: "Demand attention [N]"
                                                    onToggled: window.demandsAttention = !window.demandsAttention
                                                }

                                                // Shaded Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonShaded
                                                    checked: window?.shaded ?? false
                                                    supported: window?.shadeable ?? false
                                                    iconName: "window-shade-symbolic"
                                                    tooltipChecked: "Unshade [S]"
                                                    tooltipUnchecked: "Shade [S]"
                                                    onToggled: window.shaded = !window.shaded
                                                }

                                                // Opacity Toggle Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonTransparency
                                                    checked: isTransparent
                                                    iconName: "edit-opacity-symbolic"
                                                    tooltipChecked: "Make opaque [O]"
                                                    tooltipUnchecked: "Make transparent [O]"
                                                    onToggled: window.opacity = isTransparent ? 1.0 : settings.opacityWindow
                                                }

                                                // Skip Taskbar Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipTaskbar
                                                    checked: window?.skipTaskbar ?? false
                                                    iconName: "view-tasks-all-symbolic"
                                                    tooltipChecked: "Show in taskbar [1]"
                                                    tooltipUnchecked: "Skip taskbar [1]"
                                                    onToggled: window.skipTaskbar = !window.skipTaskbar
                                                }

                                                // Skip Switcher Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipSwitcher
                                                    checked: window?.skipSwitcher ?? false
                                                    iconName: "window-list"
                                                    tooltipChecked: "Show in switcher [2]"
                                                    tooltipUnchecked: "Skip switcher [2]"
                                                    onToggled: window.skipSwitcher = !window.skipSwitcher
                                                }

                                                // Skip Pager Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipPager
                                                    checked: window?.skipPager ?? false
                                                    iconName: "window-duplicate-symbolic"
                                                    tooltipChecked: "Show in pager [3]"
                                                    tooltipUnchecked: "Skip pager [3]"
                                                    onToggled: window.skipPager = !window.skipPager
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
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonClose ? tabBox.buttonModeOnHover : 0
                                                    supported: model.closeable
                                                    iconName: "window-close-symbolic"
                                                    tooltipUnchecked: "Close [Del]"
                                                    onToggled: {
                                                        tabBox.pendingIndex = tabBox.currentIndex
                                                        tabBox.model.close(index)
                                                    }
                                                }

                                                // Maximize/Restore Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMaximize
                                                    checked: isMaximized
                                                    supported: window?.maximizable ?? false
                                                    iconName: "window-maximize-symbolic"
                                                    iconNameChecked: "window-restore-symbolic"
                                                    tooltipChecked: "Unmaximize [PgUp]"
                                                    tooltipUnchecked: "Maximize [PgUp]"
                                                    onToggled: if (window) window.setMaximize(!isMaximized, !isMaximized)
                                                }

                                                // Maximize Horizontal Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMaximizeHorizontal
                                                    checked: isMaximizedHorizontal
                                                    supported: window?.maximizable ?? false
                                                    iconName: "transform-move-horizontal-symbolic"
                                                    tooltipChecked: "Unmaximize horizontally [End]"
                                                    tooltipUnchecked: "Maximize horizontally [End]"
                                                    // setMaximize takes (vertically, horizontally)
                                                    onToggled: if (window) window.setMaximize(isMaximizedVertical, !isMaximizedHorizontal)
                                                }

                                                // Maximize Vertical Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMaximizeVertical
                                                    checked: isMaximizedVertical
                                                    supported: window?.maximizable ?? false
                                                    iconName: "transform-move-vertical-symbolic"
                                                    tooltipChecked: "Unmaximize vertically [Home]"
                                                    tooltipUnchecked: "Maximize vertically [Home]"
                                                    // setMaximize takes (vertically, horizontally)
                                                    onToggled: if (window) window.setMaximize(!isMaximizedVertical, isMaximizedHorizontal)
                                                }

                                                // Minimize/Restore Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMinimize
                                                    checked: window?.minimized ?? false
                                                    supported: window?.minimizable ?? false
                                                    iconName: "window-minimize-symbolic"
                                                    iconNameChecked: "window-restore-symbolic"
                                                    tooltipChecked: "Unminimize [PgDn]"
                                                    tooltipUnchecked: "Minimize [PgDn]"
                                                    onToggled: window.minimized = !window.minimized
                                                }

                                                // Debug Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonDebug ? tabBox.buttonModeOnHover : 0
                                                    iconName: "info-symbolic"
                                                    tooltipUnchecked: "Show window debug info [F12]"
                                                    onToggled: executableSource.showDebugInfo(window, model.caption)
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

        SettingsPanel {
            id: settingsWnd
            visible: tabBox.showPreview

            cfg: settings
            effectModeModel: tabBox.effectModeModel
            buttonModeModel: tabBox.buttonModeModel
            isPreview: tabBox.isPreview
            toFractionString: tabBox.toFractionString

            y: 0
            anchors.horizontalCenter: parent.horizontalCenter
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
