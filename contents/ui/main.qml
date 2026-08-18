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

    Settings {
        id: settings
        category: tabBox.isAlternative ? "Alt" : "Main"
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwin_thumbnail_grid_plus.ini"
        property bool hoverSelection: true
        property int thumbnailWidthGridUnits: 16
        property string thumbnailHeightInput: "16:10"
        property int iconSizeIndex: 4
        property real backgroundOpacity: 0.5
        property real thumbnailOpacity: 1.0
        property int previewRepeatCount: 1
        property int maxWidth: 0
        property bool minimizedItalics: true
        property bool minimizedDesaturate: true
        property bool minimizedBlur: true
        property real buttonOpacity: 0.75
        property bool buttonSettings: true
        property bool buttonMaximize: true
        property bool buttonFullscreen: true
        property bool buttonNoBorder: true
        property bool buttonMinimize: true
        property bool buttonPin: true
        property bool buttonKeepAbove: true
        property bool buttonClose: true
        property bool buttonDebug: false
        property real buttonSize: 1.6
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
            onClicked: tabBox.model.activate(0)
        }

        PlasmaComponents3.Button {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Kirigami.Units.largeSpacing
            icon.name: "configure-symbolic"
            checkable: true
            checked: tabBox.showSettings
            onCheckedChanged: tabBox.showSettings = checked
            visible: settings.buttonSettings && tabBox.animationFinished
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
                    property bool sticky: false
                    onClosed: copyMenu.sourceWindow = null
                    onOpened: {
                        copyMenu.currentIndex = 0
                        copyMenu.refreshProcessInfo()
                    }
                    readonly property var asyncItems: [processPathItem, processCmdlineItem,
                                                       cwdItem, scopeItem, parentItem]
                    function refreshProcessInfo() {
                        for (let i = 0; i < copyMenu.asyncItems.length; ++i) {
                            copyMenu.asyncItems[i].value = "(loading...)"
                        }
                        const pid = copyMenu.sourceWindow?.pid
                        if (!pid) return
                        executableSource.fetch("readlink /proc/" + pid + "/exe", processPathItem, false)
                        executableSource.fetch("cat /proc/" + pid + "/cmdline | tr '\\0' ' '", processCmdlineItem, false)
                        executableSource.fetch("readlink /proc/" + pid + "/cwd", cwdItem, false)
                        executableSource.fetch("cat /proc/" + pid + "/cgroup | head -n1 | sed 's|.*/||'",
                                               scopeItem, false)
                        executableSource.fetch("ps -o ppid=,comm= -p " + pid + " | tr -s ' '",
                                               parentItem, false)
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
                    }
                    CopyItem {
                        id: processCmdlineItem
                        prefix: "Process &Args: "
                        value: "(loading...)"
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
                    }
                    CopyItem {
                        id: scopeItem
                        prefix: "Scop&e: "
                        value: "(loading...)"
                    }
                    CopyItem {
                        id: parentItem
                        prefix: "&Launched by: "
                        value: "(loading...)"
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

                // Opaque backing to match original opaque look
                Rectangle {
                    anchors.fill: parent
                    // Resize slightly to avoid bleeding out of rounded corners if SVG radius is large
                    // But mostly standard radius is fine.
                    radius: 6 // common default
                    color: Kirigami.Theme.backgroundColor
                    opacity: settings.backgroundOpacity
                }

                // Background for the window (Using standard KSVG for themed look)
                KSvg.FrameSvgItem {
                    anchors.fill: parent
                    imagePath: "dialogs/background"
                    opacity: settings.backgroundOpacity
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
                property int maxW: Math.min((settings.maxWidth > 0 ? settings.maxWidth : Infinity), tabBox.screenGeometry.width) * 0.9
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
                    } else if (key === Qt.Key_D) {
                        if (window) window.onAllDesktops = !window.onAllDesktops
                    } else if (key === Qt.Key_P) {
                        if (window) {
                            clipboard.content = String(window.pid)
                        }
                    } else if (key === Qt.Key_Space) {
                        if (window) copyMenu.show(window, currentDelegatePosition())
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

                                readonly property var window: {
                                    const windows = KWin.Workspace?.stackingOrder || [];
                                    return windows.find(w => w.internalId === windowId) || null;
                                }

                                readonly property bool isMaximized: window ?
                                    (window.frameGeometry.width >= tabBox.screenGeometry.width - 1) : false

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
                                            opacity: settings.thumbnailOpacity
                                            layer.enabled: window.minimized && !isCurrent && (settings.minimizedDesaturate || settings.minimizedBlur)
                                            layer.effect: MultiEffect {
                                                saturation: settings.minimizedDesaturate ? -1.0 : 0.0
                                                blurEnabled: settings.minimizedBlur
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

                                            // Pin to All Desktops Button
                                            Loader {
                                                id: buttonPin
                                                visible: settings.buttonPin && (window?.onAllDesktops || isCurrent || hoverHandler.hovered || (buttonPin.item ? buttonPin.item.hovered : false))
                                                sourceComponent: window?.onAllDesktops ? buttonPinTrue : buttonPinFalse

                                                Component {
                                                    id: buttonPinTrue
                                                    PlasmaComponents3.RoundButton {
                                                        icon.name: "window-pin-symbolic"
                                                        onClicked: window.onAllDesktops = !window.onAllDesktops
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Unpin from all desktops [D]"
                                                        ToolTip.visible: hovered
                                                        }
                                                    }

                                                Component {
                                                    id: buttonPinFalse
                                                    PlasmaComponents3.Button {
                                                        icon.name: "window-pin-symbolic"
                                                        onClicked: window.onAllDesktops = !window.onAllDesktops
                                                        background.opacity: settings.buttonOpacity
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Pin to all desktops [D]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }
                                            }

                                            // Keep Above Button
                                            Loader {
                                                id: buttonKeepAbove
                                                visible: settings.buttonKeepAbove && (window?.keepAbove || isCurrent || hoverHandler.hovered || (buttonKeepAbove.item ? buttonKeepAbove.item.hovered : false))
                                                sourceComponent: window?.keepAbove ? buttonKeepAboveTrue : buttonKeepAboveFalse

                                                Component {
                                                    id: buttonKeepAboveTrue
                                                    PlasmaComponents3.RoundButton {
                                                        icon.name: "window-keep-above-symbolic"
                                                        onClicked: window.keepAbove = !window.keepAbove
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Remove keep above [A]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }

                                                Component {
                                                    id: buttonKeepAboveFalse
                                                    PlasmaComponents3.Button {
                                                        icon.name: "window-keep-above-symbolic"
                                                        onClicked: window.keepAbove = !window.keepAbove
                                                        background.opacity: settings.buttonOpacity
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Keep above [A]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }
                                            }

                                            // Fullscreen Button
                                            Loader {
                                                id: buttonFullscreen
                                                visible: settings.buttonFullscreen && (window?.fullScreen || isCurrent || hoverHandler.hovered || (buttonFullscreen.item ? buttonFullscreen.item.hovered : false))
                                                sourceComponent: window?.fullScreen ? buttonFullscreenTrue : buttonFullscreenFalse

                                                Component {
                                                    id: buttonFullscreenTrue
                                                    PlasmaComponents3.RoundButton {
                                                        icon.name: "view-fullscreen-symbolic"
                                                        onClicked: window.fullScreen = !window.fullScreen
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Exit fullscreen [F]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }

                                                Component {
                                                    id: buttonFullscreenFalse
                                                    PlasmaComponents3.Button {
                                                        icon.name: "view-fullscreen-symbolic"
                                                        onClicked: window.fullScreen = !window.fullScreen
                                                        background.opacity: settings.buttonOpacity
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Fullscreen [F]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }
                                            }

                                            // No Border Button
                                            Loader {
                                                id: buttonNoBorder
                                                visible: settings.buttonNoBorder && (window?.noBorder || isCurrent || hoverHandler.hovered || (buttonNoBorder.item ? buttonNoBorder.item.hovered : false))
                                                sourceComponent: window?.noBorder ? buttonNoBorderTrue : buttonNoBorderFalse

                                                Component {
                                                    id: buttonNoBorderTrue
                                                    PlasmaComponents3.RoundButton {
                                                        icon.name: "window-decorations-symbolic"
                                                        onClicked: window.noBorder = !window.noBorder
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Show titlebar & frame [T]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }

                                                Component {
                                                    id: buttonNoBorderFalse
                                                    PlasmaComponents3.Button {
                                                        icon.name: "window-decorations-symbolic"
                                                        onClicked: window.noBorder = !window.noBorder
                                                        background.opacity: settings.buttonOpacity
                                                        implicitWidth: buttonSize
                                                        implicitHeight: buttonSize
                                                        ToolTip.text: "Hide titlebar & frame [T]"
                                                        ToolTip.visible: hovered
                                                    }
                                                }
                                            }

                                            Item {
                                                Layout.fillWidth: true
                                            }

                                            // Debug Button
                                            PlasmaComponents3.Button {
                                                id: buttonDebug
                                                visible: settings.buttonDebug && (isCurrent || hoverHandler.hovered || buttonDebug.hovered)
                                                icon.name: "info-symbolic"
                                                onClicked: executableSource.showDebugInfo(window, model.caption)
                                                background.opacity: settings.buttonOpacity
                                                implicitWidth: buttonSize
                                                implicitHeight: buttonSize
                                                ToolTip.text: "Show window debug info [F12]"
                                                ToolTip.visible: hovered
                                            }

                                            // Minimize/Restore Button
                                            PlasmaComponents3.Button {
                                                id: minRestoreButton
                                                visible: settings.buttonMinimize && (isCurrent || hoverHandler.hovered || minRestoreButton.hovered)
                                                icon.name: window?.minimized ? "window-restore-symbolic" : "window-minimize-symbolic"
                                                onClicked: window.minimized = !window.minimized
                                                background.opacity: settings.buttonOpacity
                                                implicitWidth: buttonSize
                                                implicitHeight: buttonSize
                                                ToolTip.text: window?.minimized ? "Restore [PgDn]" : "Minimize [PgDn]"
                                                ToolTip.visible: hovered
                                            }

                                            // Maximize/Restore Button
                                            PlasmaComponents3.Button {
                                                id: buttonMaximize
                                                visible: settings.buttonMaximize && (isCurrent || hoverHandler.hovered || buttonMaximize.hovered)
                                                icon.name: isMaximized ? "window-restore-symbolic" : "window-maximize-symbolic"
                                                onClicked: if (window) {
                                                    window.setMaximize(!isMaximized, !isMaximized)
                                                }
                                                background.opacity: settings.buttonOpacity
                                                implicitWidth: buttonSize
                                                implicitHeight: buttonSize
                                                ToolTip.text: isMaximized ? "Restore [PgUp]" : "Maximize [PgUp]"
                                                ToolTip.visible: hovered
                                            }

                                            // Close Button
                                            PlasmaComponents3.Button {
                                                id: buttonClose
                                                visible: settings.buttonClose && model.closeable && (isCurrent || hoverHandler.hovered || buttonClose.hovered)
                                                icon.name: "window-close-symbolic"
                                                onClicked: {
                                                    tabBox.pendingIndex = tabBox.currentIndex
                                                    tabBox.model.close(index)
                                                }
                                                background.opacity: settings.buttonOpacity
                                                implicitWidth: buttonSize
                                                implicitHeight: buttonSize
                                                ToolTip.text: "Close [Del]"
                                                ToolTip.visible: hovered
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
                                            opacity: settings.thumbnailOpacity
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
                                                opacity: settings.thumbnailOpacity
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
                                                opacity: settings.thumbnailOpacity
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
                                        font.italic: window.minimized && settings.minimizedItalics
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
                            text: "Select with mouse hover"
                            checked: settings.hoverSelection
                            onCheckedChanged: settings.hoverSelection = checked
                        }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents3.CheckBox {
                            text: "Show windowing protocol"
                            checked: settings.showProtocol
                            onCheckedChanged: settings.showProtocol = checked
                        }
                        Item { Layout.fillWidth: true }
                        PlasmaComponents3.CheckBox {
                            text: "Settings button"
                            checked: settings.buttonSettings
                            onCheckedChanged: settings.buttonSettings = checked
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Max width:" }
                        PlasmaComponents3.Slider {
                            id: maxWidthSlider
                            from: 0
                            to: tabBox.screenGeometry.width
                            value: Math.min(settings.maxWidth, tabBox.screenGeometry.width)
                            stepSize: 1
                            onMoved: settings.maxWidth = Math.round(value)
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.SpinBox {
                            from: 0
                            to: 99999
                            value: settings.maxWidth
                            onValueModified: settings.maxWidth = value
                        }
                        PlasmaComponents3.Label { text: "px" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Minimized windows:" }
                        PlasmaComponents3.CheckBox {
                            text: "Italics text"
                            checked: settings.minimizedItalics
                            onCheckedChanged: settings.minimizedItalics = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Desaturate thumbnail"
                            checked: settings.minimizedDesaturate
                            onCheckedChanged: settings.minimizedDesaturate = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Blur thumbnail"
                            checked: settings.minimizedBlur
                            onCheckedChanged: settings.minimizedBlur = checked
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
                            value: settings.thumbnailOpacity
                            stepSize: 0.01
                            onMoved: settings.thumbnailOpacity = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.thumbnailOpacity * 100) + "%"
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
                            value: settings.backgroundOpacity
                            stepSize: 0.01
                            onMoved: settings.backgroundOpacity = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.backgroundOpacity * 100) + "%"
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
                            value: settings.buttonOpacity
                            stepSize: 0.01
                            onMoved: settings.buttonOpacity = value
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(settings.buttonOpacity * 100) + "%"
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
                        PlasmaComponents3.Label { text: "Window status buttons:" }
                        PlasmaComponents3.CheckBox {
                            text: "Pin to all desktops"
                            checked: settings.buttonPin
                            onCheckedChanged: settings.buttonPin = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Keep above"
                            checked: settings.buttonKeepAbove
                            onCheckedChanged: settings.buttonKeepAbove = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Fullscreen"
                            checked: settings.buttonFullscreen
                            onCheckedChanged: settings.buttonFullscreen = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "No titlebar/frame"
                            checked: settings.buttonNoBorder
                            onCheckedChanged: settings.buttonNoBorder = checked
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Window action buttons:" }
                        PlasmaComponents3.CheckBox {
                            text: "Debug"
                            checked: settings.buttonDebug
                            onCheckedChanged: settings.buttonDebug = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Minimize/Restore"
                            checked: settings.buttonMinimize
                            onCheckedChanged: settings.buttonMinimize = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Maximize/Restore"
                            checked: settings.buttonMaximize
                            onCheckedChanged: settings.buttonMaximize = checked
                        }
                        PlasmaComponents3.CheckBox {
                            text: "Close"
                            checked: settings.buttonClose
                            onCheckedChanged: settings.buttonClose = checked
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
        property var _pending: ({})
        function fetch(cmd, item, copy) {
            executableSource._pending[cmd] = { "item": item, "copy": copy }
            executableSource.connectSource(cmd)
        }
        onNewData: {
            const req = executableSource._pending[sourceName]
            if (req) {
                const result = String(data.stdout).trim()
                if (req.item) req.item.value = result
                if (req.copy) clipboard.content = result
                delete executableSource._pending[sourceName]
            }
            executableSource.disconnectSource(sourceName)
        }

        function showDebugInfo(window, caption) {
            var text = dumpProperties(window)
            var cmd = "echo '" + text.replace(/'/g, "'\\''") + "' > /tmp/kwin_debug_window.txt && kdialog --textbox /tmp/kwin_debug_window.txt --title 'KWin: " + caption + "' --geometry 480x600"
            executableSource.connectSource(cmd)
        }
    }
}
