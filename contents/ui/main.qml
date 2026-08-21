/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
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

    // Splits "16:9" into [16, 9], or null if it is not a pair of positive numbers.
    function splitRatio(input) {
        const parts = (input || "").trim().split(":")
        if (parts.length !== 2) return null
        const x = parseFloat(parts[0])
        const y = parseFloat(parts[1])
        if (isNaN(x) || isNaN(y) || x <= 0 || y <= 0) return null
        return [x, y]
    }

    // True for input that is meant as a ratio but is not a usable one, so
    // callers can reject it instead of falling through to parseFloat() - which
    // would read "16:9" as plain 16.
    function looksLikeRatio(input) {
        return (input || "").includes(":")
    }

    function parseAspectRatio(input) {
        const s = (input || "").trim()
        if (!s) return 0
        const ratio = splitRatio(s)
        if (ratio) return ratio[0] / ratio[1]
        if (looksLikeRatio(s)) return 0
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
        property real hoverSelectionMinDeltaGU: 1.0
        property bool showSettingsButton: true
        property bool showSettingsAfterPreview: true
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

        property int buttonKill: 5
        // Seconds between SIGTERM and the SIGKILL follow-up.
        property int killGraceSeconds: 3

        property bool buttonClose: true
        // Milliseconds the Close button (or Delete) must be held to kill the
        // window's process instead of closing it; 0 disables hold-to-kill.
        property int closeHoldMs: 2000
        property bool buttonDebug: false
    }

    // Defaults for SettingsPanel's "differs from defaults" count and its Restore
    // defaults button. QtCore.Settings has no API for a property's initialiser
    // once it has been overwritten from disk, so this has to mirror the block
    // above by hand; keep the two in sync when adding a setting.
    readonly property var settingsDefaults: ({
        hoverSelection: true,
        hoverSelectionMinDeltaGU: 1.0,
        showSettingsButton: true,
        showSettingsAfterPreview: false,
        showProtocol: true,
        lockGridWidth: true,
        centerHighlightButtons: true,

        thumbnailWidthGridUnits: 16,
        thumbnailHeightInput: "16:10",
        maxGridAspectRatioInput: "21:9",

        previewRepeatCount: 1,
        buttonSize: 1.6,

        opacityBackground: 0.5,
        opacityThumbnail: 1.0,
        opacityWindowButton: 0.75,
        opacityWindow: 0.7,

        iconSizeIndex: 4,

        minimizedItalics: 1,
        minimizedBlur: 2,
        minimizedContrast: 1,
        minimizedThumbnailOpacity: 0,
        minimizedThumbnailScale: 0,
        minimizedThumbnailRotation: 2,
        minimizedIconOpacity: 1,
        minimizedStrikethrough: 0,
        minimizedUnderline: 0,
        minimizedIcon: 0,

        buttonMaximize: 2,
        buttonMaximizeHorizontal: 0,
        buttonMaximizeVertical: 0,
        buttonFullscreen: 1,
        buttonNoBorder: 1,
        buttonMinimize: 2,
        buttonPin: 1,
        buttonKeepAbove: 1,
        buttonKeepBelow: 5,
        buttonIncognito: 5,
        buttonDemandsAttention: 5,
        buttonShaded: 5,
        buttonTransparency: 5,
        buttonSkipTaskbar: 5,
        buttonSkipPager: 5,
        buttonSkipSwitcher: 5,

        buttonKill: 5,
        killGraceSeconds: 3,

        buttonClose: true,
        closeHoldMs: 2000,
        buttonDebug: false,
    })

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

    // Keyboard auto-repeat timing, as configured by the user in System Settings
    // -> Keyboard -> Key repeat (KWin applies these to the Wayland seat's
    // repeat_info; on X11 they are the XKB repeat delay/rate). Hold-to-kill has
    // to infer "still held" from auto-repeat presses, so it needs the real
    // values rather than a guessed constant. These are the Plasma defaults,
    // used until the read below comes back, and if the keys are unset.
    property int keyRepeatDelay: 600   // ms before repeating starts
    property int keyRepeatRate: 25     // repeats per second thereafter
    readonly property string keyRepeatCommand:
        "kreadconfig6 --file kcminputrc --group Keyboard --key RepeatDelay --default 600;"
        + " kreadconfig6 --file kcminputrc --group Keyboard --key RepeatRate --default 25"

    function applyKeyRepeat(stdout) {
        const lines = String(stdout).trim().split("\n")
        const delay = parseFloat(lines[0])
        const rate = parseFloat(lines[1])
        if (delay > 0) keyRepeatDelay = Math.round(delay)
        if (rate > 0) keyRepeatRate = Math.round(rate)
    }

    readonly property real buttonSize: Kirigami.Units.gridUnit * settings.buttonSize
    readonly property bool isAlternative: false  // tabBox.mode is undefined
    readonly property bool isPreview: tabBox.automaticallyHide === undefined
    readonly property bool showPreview: isPreview || showSettings
    property bool showSettings: false
    property bool animationFinished: false

    // Guards the popup <-> window handover below: one host is closed before the
    // other opens, and without this that close would clear `showSettings`.
    property bool movingSettings: false

    // Keeps exactly one settings host open: the popup while the switcher is on
    // screen (a real window would stack behind KWin's overlay), the standalone
    // window once the switcher is gone. Same split as editPopup/editWindow.
    function updateSettingsHost() {
        const wantPopup = showPreview && wrapper.visible
        const wantWindow = showPreview && !wrapper.visible
            && (!isPreview || settings.showSettingsAfterPreview)

        movingSettings = true
        if (!wantPopup && settingsPopup.opened) {
            if (wantWindow)
                settingsWindowContent.adoptStateFrom(settingsPopup)
            settingsPopup.close()
        }
        if (!wantWindow && settingsWindow.visible) {
            if (wantPopup)
                settingsPopup.adoptStateFrom(settingsWindowContent)
            settingsWindow.close()
        }
        // The panel sets `focus: true`, so opening hands it the keyboard.
        if (wantPopup && !settingsPopup.opened)
            settingsPopup.open()
        if (wantWindow && !settingsWindow.visible) {
            settingsWindowContent.open()
            settingsWindow.show()
            settingsWindow.x = tabBox.screenGeometry.x
            settingsWindow.y = tabBox.screenGeometry.y
            settingsWindow.requestActivate()
        }
        movingSettings = false
    }

    onShowPreviewChanged: {
        updateSettingsHost()
        if (!showPreview)
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
            // The settings panel follows the switcher between its two hosts.
            tabBox.updateSettingsHost()
        }
        color: "transparent"
        width: tabBox.screenGeometry.width
        height: tabBox.screenGeometry.height

        MouseArea {
            anchors.fill: parent
            onClicked: isPreview ? wrapper.close() : tabBox.model.activate(0)
        }

        PlasmaComponents3.Button {
            id: settingsButton
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Kirigami.Units.largeSpacing
            icon.name: "configure-symbolic"
            checkable: true
            checked: tabBox.showSettings
            onCheckedChanged: tabBox.showSettings = checked
            visible: settings.showSettingsButton && tabBox.animationFinished
            PlasmaComponents3.ToolTip.text: i18n("Settings [F2]")
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        Item {
            id: wnd
            anchors.centerIn: parent
            
            // Main Item Container
            FocusScope {
                id: dialogMainItem
                focus: true
                anchors.fill: parent

                property point hoverArmPosition: Qt.point(0, 0)
                property bool hoverArmPositionSet: false
                property bool hoverThresholdMet: false
                // Last pointer position in scene coordinates, used to tell real
                // cursor movement apart from point updates caused by the grid
                // relayouting under a stationary cursor.
                property point hoverLastScenePosition: Qt.point(0, 0)
                property bool hoverLastScenePositionSet: false
                // Set while the hover handler itself is changing the selection, so
                // that the resulting currentIndex change isn't mistaken for a
                // keyboard selection and doesn't re-arm the dead zone.
                property bool hoverSelecting: false

                // Require the cursor to travel the dead zone again before hover
                // selection may take over (e.g. after keyboard navigation).
                function rearmHoverSelection() {
                    hoverArmPosition = hoverLastScenePosition
                    hoverArmPositionSet = hoverLastScenePositionSet
                    hoverThresholdMet = false
                }

                Clipboard { id: clipboard }

                CopyMenu {
                    id: copyMenu
                    isX11Window: tabBox.isX11Window
                    onCopyRequested: text => clipboard.content = text
                    onNavigateRequested: key => dialogMainItem.navigate(key)
                    onCommandRequested: command => executableSource.connectSource(command)
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

                    // Try aspect ratio "X:Y" (or "XxY")
                    const ratio = tabBox.splitRatio(input);
                    if (ratio) {
                        return Math.round(thumbnailWidth * (ratio[1] / ratio[0]));
                    }

                    // Try plain positive number (gridUnits), but never read a
                    // malformed ratio as just its first number.
                    const num = parseFloat(input);
                    if (!tabBox.looksLikeRatio(input) && !isNaN(num) && num > 0) {
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

                // Hold-to-kill for the Delete key.
                //
                // KWin's tab box grabs the keyboard and only forwards key
                // *presses* to the QML view — releases are consumed for its own
                // modifier handling — so "still held" can only be inferred from
                // auto-repeat presses arriving, and "released" from them
                // stopping. Delete therefore keeps closing on the press, and
                // holding it escalates to a kill once closeHoldMs has passed;
                // on a window that closed normally the escalation never gets
                // there, and on a wedged one the close was ignored anyway.
                property bool closeHoldArmed: false
                // A hold is only *known* to be a hold once auto-repeat confirms
                // the key is still down, one repeat delay after the press. The
                // progress indicator waits for that rather than flashing red on
                // every Delete tap, and picks up at the elapsed time below.
                property bool closeHoldConfirmed: false
                property int closeHoldConfirmedMs: 0
                property double closeHoldConfirmedAt: 0
                property bool closeHoldFired: false
                property double closeHoldStart: 0
                property int closeHoldPid: 0
                // internalId of the window the hold began on, so a hold can
                // never escalate onto whatever got selected after it closed.
                property var closeHoldWindow: null

                // Whether the window the hold began on is still around. Asking
                // that of the workspace rather than of the selection keeps the
                // hold alive across model changes: a window opening or closing
                // elsewhere shifts what currentIndex points at, which is not
                // the hold's target changing.
                function closeHoldTargetAlive() {
                    if (closeHoldWindow === null) return false
                    const windows = KWin.Workspace?.stackingOrder || []
                    return windows.some(w => w.internalId === closeHoldWindow)
                }

                function closeWindowAt(index) {
                    if (index < 0 || tabBox.pendingIndex >= 0) return
                    tabBox.pendingIndex = tabBox.currentIndex
                    tabBox.model.close(index)
                }

                function cancelCloseHold() {
                    closeRepeatTimer.stop()
                    closeHoldArmed = false
                    closeHoldConfirmed = false
                    closeHoldConfirmedMs = 0
                    closeHoldConfirmedAt = 0
                    closeHoldFired = false
                    closeHoldWindow = null
                }

                // A repeat that doesn't arrive means the key is no longer down.
                // The first one has to wait out the user's repeat delay; once
                // repeats are flowing they come every 1000/rate ms.
                Timer {
                    id: closeRepeatTimer
                    interval: dialogMainItem.firstRepeatInterval
                    onTriggered: dialogMainItem.cancelCloseHold()
                }

                // Both allow a wide margin: missing a repeat disarms a hold the
                // user is still holding, and the kill never fires.
                readonly property int firstRepeatInterval: tabBox.keyRepeatDelay + 250
                readonly property int nextRepeatInterval:
                    Math.max(150, Math.round(3000 / Math.max(1, tabBox.keyRepeatRate)))

                // Whether KWin's tab box marks forwarded auto-repeats as such.
                // It grabs the keyboard and re-sends key events itself, so the
                // flag can arrive cleared; once one is seen it is trusted, and
                // rapid Delete taps keep closing one window each.
                property bool autoRepeatFlagged: false
                property double closeHoldLast: 0

                // A held Delete looks like a stream of presses. With no usable
                // isAutoRepeat, fall back to their timing: anything arriving
                // inside the window the watchdog is currently waiting on (the
                // repeat delay before the first repeat, the repeat interval
                // after) is part of the same hold rather than a new press.
                function isCloseRepeat(event) {
                    const now = Date.now()
                    const sinceLast = now - closeHoldLast
                    closeHoldLast = now
                    if (autoRepeatFlagged) return event.isAutoRepeat
                    // Once the hold's window is gone it closed as asked, so a
                    // further press is a new one however fast it arrived.
                    return closeHoldArmed && closeHoldTargetAlive()
                        && sinceLast <= closeRepeatTimer.interval
                }

                function beginCloseHold() {
                    const win = currentWindow()
                    closeHoldPid = win?.pid ?? 0
                    closeHoldWindow = win?.internalId ?? null
                    closeHoldConfirmed = false
                    closeHoldConfirmedMs = 0
                    closeHoldConfirmedAt = 0
                    closeHoldFired = false
                    closeHoldStart = Date.now()
                    closeWindowAt(tabBox.currentIndex)
                    closeHoldArmed = settings.closeHoldMs > 0 && closeHoldPid > 0
                    if (closeHoldArmed) {
                        closeRepeatTimer.interval = firstRepeatInterval
                        closeRepeatTimer.restart()
                    }
                }

                // Called for each auto-repeat of a held Delete.
                function continueCloseHold() {
                    if (!closeHoldArmed) return
                    // The window the hold began on is gone, so it closed like
                    // it was asked to. There is nothing to escalate to, and its
                    // pid may still own windows the user never asked to close.
                    if (!closeHoldTargetAlive()) {
                        cancelCloseHold()
                        return
                    }
                    closeRepeatTimer.interval = nextRepeatInterval
                    closeRepeatTimer.restart()
                    if (!closeHoldConfirmed) {
                        closeHoldConfirmedMs =
                            Math.min(Date.now() - closeHoldStart, settings.closeHoldMs)
                        closeHoldConfirmedAt = Date.now()
                        closeHoldConfirmed = true
                    }
                    if (closeHoldFired) return
                    if (Date.now() - closeHoldStart < settings.closeHoldMs) return
                    closeHoldFired = true
                    tabBox.pendingIndex = tabBox.currentIndex
                    executableSource.killPid(closeHoldPid)
                }

                function handleSpecialKeys(key) {
                    const idx = tabBox.model.index(tabBox.currentIndex, 0)
                    const window = currentWindow()

                    if (key === Qt.Key_PageUp) {
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
                    } else if (key === Qt.Key_F2) {
                        tabBox.showSettings = !tabBox.showSettings
                    } else if (key === Qt.Key_F12) {
                        var caption = tabBox.model.data(idx, captionRole)
                        executableSource.showDebugInfo(window, caption)
                    } else {
                        return false;
                    }
                    return true;
                }

                Keys.onPressed: (event) => {
                    if (event.isAutoRepeat) autoRepeatFlagged = true
                    if (event.key === Qt.Key_Delete) {
                        event.accepted = true
                        if (isCloseRepeat(event)) {
                            continueCloseHold()
                        } else {
                            beginCloseHold()
                        }
                        return
                    }
                    // Any other key means Delete is no longer what's held down.
                    cancelCloseHold()
                    if (navigate(event.key)) { event.accepted = true; return; }
                    if (handleSpecialKeys(event.key)) { event.accepted = true; return; }
                }


                Timer {
                    id: armTimer
                    interval: Kirigami.Units.veryLongDuration
                    onTriggered: {
                        tabBox.animationFinished = true
                        dialogMainItem.hoverArmPositionSet = false
                        dialogMainItem.hoverThresholdMet = false
                        dialogMainItem.hoverLastScenePositionSet = false
                    }
                }

                Connections {
                    target: tabBox
                    function onCurrentIndexChanged() {
                        if (!dialogMainItem.hoverSelecting)
                            dialogMainItem.rearmHoverSelection()
                        if (copyMenu.sticky) reopenCopyMenuTimer.restart()
                    }
                    function onVisibleChanged() {
                        dialogMainItem.cancelCloseHold()
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
                            if (editPopup.opened && editPopup.targetWindow) {
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
                                    && (settings.hoverSelectionMinDeltaGU <= 0
                                        || dialogMainItem.hoverThresholdMet
                                        || !tabBox.animationFinished)
                                readonly property real buttonSize: tabBox.buttonSize
                                readonly property real buttonBackgroundOpacity: settings.opacityWindowButton

                                function effectActive(mode) {
                                    if (!window || !window.minimized) return false;
                                    switch (mode) {
                                        case 0: return false;
                                        case 1: return true;
                                        case 2: return !hovered && !isCurrent;
                                        case 3: return !hovered;
                                        case 4: return !isCurrent;
                                        default: return false;
                                    }
                                }

                                readonly property var window: {
                                    const windows = KWin.Workspace?.stackingOrder || [];
                                    return windows.find(w => w.internalId === windowId) || null;
                                }

                                property bool maximizable: window?.maximizable ?? false
                                property bool minimizable: window?.minimizable ?? false

                                Connections {
                                    target: window
                                    function onMaximizeableChanged() { maximizable = window.maximizable }
                                    function onMinimizeableChanged() { minimizable = window.minimizable }
                                    function onFullScreenChanged() {
                                        maximizable = window.maximizable
                                        minimizable = window.minimizable
                                    }
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

                                HoverHandler {
                                    id: selectionHoverHandler
                                    enabled: settings.hoverSelection && tabBox.animationFinished
                                    onPointChanged: {
                                        // This also fires when the cell moves or resizes under a stationary
                                        // cursor (e.g. the grid relayouting after a keyboard selection
                                        // change). Scene coordinates are unaffected by that, so ignore any
                                        // update that isn't real cursor movement -- otherwise hover would
                                        // immediately undo arrow/tab navigation.
                                        const scenePos = point.scenePosition
                                        if (dialogMainItem.hoverLastScenePositionSet
                                                && scenePos.x === dialogMainItem.hoverLastScenePosition.x
                                                && scenePos.y === dialogMainItem.hoverLastScenePosition.y)
                                            return
                                        dialogMainItem.hoverLastScenePosition = scenePos
                                        dialogMainItem.hoverLastScenePositionSet = true
                                    
                                        const minDelta = settings.hoverSelectionMinDeltaGU * Kirigami.Units.gridUnit
                                        if (minDelta > 0 && !dialogMainItem.hoverThresholdMet) {
                                            if (!dialogMainItem.hoverArmPositionSet) {
                                                dialogMainItem.hoverArmPosition = scenePos
                                                dialogMainItem.hoverArmPositionSet = true
                                                return
                                            }
                                            const dx = scenePos.x - dialogMainItem.hoverArmPosition.x
                                            const dy = scenePos.y - dialogMainItem.hoverArmPosition.y
                                            if (Math.sqrt(dx * dx + dy * dy) < minDelta)
                                                return
                                            dialogMainItem.hoverThresholdMet = true
                                        }
                                        dialogMainItem.hoverSelecting = true
                                        tabBox.currentIndex = index
                                        dialogMainItem.hoverSelecting = false
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: tabBox.model.activate(index)
                                    
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

                                            readonly property bool centerButtons: settings.centerHighlightButtons && !isCurrent && !hovered

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

                                                // Kill Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonKill
                                                    checked: window?.unresponsive ?? false
                                                    supported: (window?.pid ?? 0) > 0  // Remote X11 clients report no usable PID (not supported)
                                                    iconName: "process-stop-symbolic"
                                                    tooltipChecked: "Kill process\n(Window is unresponsive)"
                                                    tooltipUnchecked: "Kill process"
                                                    onToggled: {
                                                        tabBox.pendingIndex = tabBox.currentIndex
                                                        executableSource.killPid(window?.pid ?? 0)
                                                    }
                                                }

                                                // Close Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonClose ? tabBox.buttonModeOnHover : 0
                                                    supported: model.closeable
                                                    iconName: "window-close-symbolic"
                                                    tooltipUnchecked: holdEnabled ? "Close [Del]\nHold to kill" : "Close [Del]"
                                                    holdMs: settings.closeHoldMs
                                                    // Remote X11 clients report no usable PID; close only.
                                                    holdSupported: (window?.pid ?? 0) > 0
                                                    // Mirror a hold driven from the keyboard on the selected cell.
                                                    holdExternal: cell.isCurrent && dialogMainItem.closeHoldConfirmed
                                                    holdStartedMs: dialogMainItem.closeHoldConfirmedMs
                                                    holdExternalStart: dialogMainItem.closeHoldConfirmedAt
                                                    holdExternalFired: dialogMainItem.closeHoldFired
                                                    onToggled: {
                                                        tabBox.pendingIndex = tabBox.currentIndex
                                                        tabBox.model.close(index)
                                                    }
                                                    onHeld: {
                                                        tabBox.pendingIndex = tabBox.currentIndex
                                                        executableSource.killPid(window?.pid ?? 0)
                                                    }
                                                }

                                                // Maximize/Restore Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMaximize
                                                    checked: isMaximized
                                                    supported: maximizable
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
                                                    supported: maximizable
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
                                                    supported: maximizable
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
                                                    supported: minimizable
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

        // Left screen edge, full height. Draggable and resizable from there.
        SettingsPanel {
            id: settingsPopup

            cfg: settings
            defaults: tabBox.settingsDefaults
            effectModeModel: tabBox.effectModeModel
            buttonModeModel: tabBox.buttonModeModel
            isPreview: tabBox.isPreview
            toFractionString: tabBox.toFractionString
            maxGridAspectRatio: dialogMainItem.maxGridAspectRatioValue

            x: 0
            y: 0
            // Reset size each time the popup opens so it matches the current
            // screen resolution (the resize grip takes over from here).
            // End above the settings button so it stays clickable.
            onVisibleChanged: if (visible)
                height = wrapper.height - settingsButton.height - Kirigami.Units.largeSpacing * 2

            onResetPosition: {
                settingsPopup.x = 0
                settingsPopup.y = 0
                settingsPopup.width = Kirigami.Units.gridUnit * 46
                settingsPopup.height = wrapper.height
                                       - settingsButton.height
                                       - Kirigami.Units.largeSpacing * 2
            }
            onClosed: if (!settingsWindow.visible) tabBox.showSettings = false
        }
    }

    // The same panel once the switcher is gone, so settings opened during
    // alt-tab stay open and editable afterwards.
    Window {
        id: settingsWindow
        visible: false
        flags: Qt.Window | Qt.WindowStaysOnTopHint
        color: Kirigami.Theme.backgroundColor
        title: "Thumbnail Grid ++ — " + settings.category + " profile"
        width: Kirigami.Units.gridUnit * 46
        height: tabBox.screenGeometry.height

        onClosing: if (!tabBox.movingSettings) tabBox.showSettings = false

        SettingsPanel {
            id: settingsWindowContent
            showChrome: false
            x: 0
            y: 0
            width: parent.width
            height: parent.height

            cfg: settings
            defaults: tabBox.settingsDefaults
            effectModeModel: tabBox.effectModeModel
            buttonModeModel: tabBox.buttonModeModel
            isPreview: tabBox.isPreview
            toFractionString: tabBox.toFractionString
            maxGridAspectRatio: dialogMainItem.maxGridAspectRatioValue

            onResetPosition: {
                settingsWindow.x = tabBox.screenGeometry.x
                settingsWindow.y = tabBox.screenGeometry.y
                settingsWindow.width = Kirigami.Units.gridUnit * 46
            }
            onClosed: settingsWindow.close()
        }
    }

    Plasma5Support.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []
        // Replies are routed by matching sourceName against each item's current
        // `command` binding, so there is no long-lived request map to mutate.
        onNewData: (sourceName, data) => {
            if (sourceName === tabBox.keyRepeatCommand) {
                tabBox.applyKeyRepeat(String(data.stdout))
                executableSource.disconnectSource(sourceName)
                return
            }
            copyMenu.deliverResult(sourceName, String(data.stdout).trim())
            executableSource.disconnectSource(sourceName)
        }

        Component.onCompleted: executableSource.readKeyRepeat()

        // Reads the user's keyboard auto-repeat timing, which hold-to-kill needs
        // to tell a held Delete from a tapped one. See tabBox.keyRepeatDelay.
        function readKeyRepeat() {
            executableSource.connectSource(tabBox.keyRepeatCommand)
        }

        // Window.killWindow() is not exposed to QML
        function killPid(pid) {
            if (!(pid > 0)) return
            executableSource.connectSource(
                "kill -TERM " + pid + " 2>/dev/null;"
                + " setsid sh -c 'sleep " + settings.killGraceSeconds
                + "; kill -0 " + pid + " 2>/dev/null"
                + " && kill -KILL " + pid + "' </dev/null >/dev/null 2>&1 &")
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
