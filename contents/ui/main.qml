/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
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
import "keyutils.js" as KeyUtils

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
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwin_thumbnail_grid_pp.ini"

        property bool hoverSelection: true
        property real hoverSelectionMinDeltaGU: 1.0
        property bool showSettingsButton: true
        property bool showSettingsAfterPreview: true
        property bool showProtocol: true
        property bool lockGridWidth: true
        property bool lockGridYPosition: true
        property bool centerHighlightButtons: true

        property int thumbnailWidthGridUnits: 16
        property string thumbnailHeightInput: "16:10"
        property string maxGridAspectRatioInput: "21:9"
        property real gridWidthFraction: 0.9
        property real gridHeightFraction: 0.8

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
        property bool dumpSortKeys: false

        // Keyboard shortcut key codes (Qt.Key_* values). 0 = no shortcut.
        property int shortcutPin: Qt.Key_D
        property int shortcutKeepAbove: Qt.Key_A
        property int shortcutKeepBelow: Qt.Key_B
        property int shortcutFullscreen: Qt.Key_F
        property int shortcutNoBorder: Qt.Key_T
        property int shortcutIncognito: Qt.Key_I
        property int shortcutDemandsAttention: Qt.Key_N
        property int shortcutShaded: Qt.Key_S
        property int shortcutTransparency: Qt.Key_O
        property int shortcutSkipTaskbar: Qt.Key_Q
        property int shortcutSkipSwitcher: 0
        property int shortcutSkipPager: 0
        property int shortcutMaximize: Qt.Key_PageUp
        property int shortcutMaximizeHorizontal: Qt.Key_End
        property int shortcutMaximizeVertical: Qt.Key_Home
        property int shortcutMinimize: Qt.Key_PageDown
        property int shortcutKill: 0
        property int shortcutClose: Qt.Key_Delete
        // Non-button shortcuts:
        property int shortcutCopyPid: Qt.Key_P
        property int shortcutCopyMenu: Qt.Key_Space
        property int shortcutEdit: Qt.Key_E
        property int shortcutSettings: Qt.Key_F2
        property int shortcutShortcutsPopup: Qt.Key_F1

        // User-defined shell commands, one per slot: slot i is the command
        // key `command<i>`, bound to the shortcut key code `commandShortcut<i>`
        // (0 = no shortcut). The command string is expanded (see
        // tabBox.expandPlaceholders) and run by the executable data engine; an
        // empty string disables the slot.
        //
        // Only the two default slots are declared here - the settings panel adds
        // and removes slots at runtime, and those live purely in the config file,
        // read and written with Settings.value()/setValue(). commandCount is what
        // says how many slots exist; see commandAt() and friends below.
        property int commandCount: 2
        property int commandShortcut0: Qt.Key_0
        property string command0: "echo {{' dump(w) }} > /tmp/tgpp_debug.txt && kdialog --textbox /tmp/tgpp_debug.txt --title {{' \"[TG++ Debug] \" + w.caption }} --geometry 480x600 {% close() %}"
        property int commandShortcut1: Qt.Key_1
        property string command1: "{{term}} btop -p 1 -f '!^{{w.pid}}$' {% close() %}"

        // Extra names visible to custom-command placeholders, as the body of a
        // JSON object (the surrounding braces are implied).
        property string placeholders: '"term": "konsole -e"'

        // Names visible to a placeholder on top of the window's own properties,
        // parsed out of the `placeholders` setting; a half-typed value simply
        // parses as nothing. A function rather than a property because Settings
        // persists its properties: this one would be written to the config file
        // and then restored over its own binding on the next start.
        function placeholderDict() {
            try {
                return JSON.parse("{" + placeholders.replace(/,\s*$/, "") + "}")
            } catch (e) {
                return ({})
            }
        }

        // Bumped by every slot edit below. Settings.value() is a plain function
        // call and notifies nothing, so commandAt/shortcutAt read this too (any
        // property touched while a binding evaluates becomes a dependency,
        // including inside the functions it calls) and their bindings re-evaluate
        // when it changes. Declared here like any setting, so it is written to
        // the config file; it is not a setting anyone should edit, hence the _.
        property int _commandsRevision: 0

        // Slot accessors and mutators. The first slots are declared properties
        // above; the rest are config keys with no property behind them, hence the
        // value()/setValue() fallback. Values read from the file come back as
        // strings, so key codes are coerced back to numbers.
        //
        // These live here rather than on tabBox because a slot is nothing but
        // config: everything below is a read or a write of this object.
        function commandAt(index) {
            //const rev = _commandsRevision // read for the dependency
            const declared = settings["command" + index]
            return declared !== undefined ? declared
                                          : String(settings.value("command" + index, ""))
        }

        function shortcutAt(index) {
            //const rev = _commandsRevision // read for the dependency
            const declared = settings["commandShortcut" + index]
            return declared !== undefined ? declared
                                          : Number(settings.value("commandShortcut" + index, 0)) || 0
        }

        function setCommandAt(index, text) {
            if (settings["command" + index] !== undefined)
                settings["command" + index] = text
            else
                settings.setValue("command" + index, text)
            //++_commandsRevision
        }

        function setShortcutAt(index, keyCode) {
            if (settings["commandShortcut" + index] !== undefined)
                settings["commandShortcut" + index] = keyCode
            else
                settings.setValue("commandShortcut" + index, keyCode)
            //++_commandsRevision
        }

        // The new slot follows on from the last one's key (Key_1 -> Key_2), which
        // is the right guess often enough to save a keystroke. An unbound last
        // slot leaves the new one unbound too. Past Key_9 the next key code is a
        // colon, so the run carries on at Key_F3 instead (F1 and F2 are taken by
        // the shortcuts popup and the settings panel).
        function addCommand() {
            const index = settings.commandCount
            const previous = index > 0 ? shortcutAt(index - 1) : 0
            let next = previous ? previous + 1 : 0
            if (next === Qt.Key_9 + 1) next = Qt.Key_F3
            setCommandAt(index, "")
            setShortcutAt(index, next)
            settings.commandCount = index + 1
        }

        // Slots are identified by position, so removing one shifts the rest down;
        // the now-unused last slot is cleared so a later add starts empty.
        function removeCommand(index) {
            const last = settings.commandCount - 1
            for (var i = index; i < last; ++i) {
                setCommandAt(i, commandAt(i + 1))
                setShortcutAt(i, shortcutAt(i + 1))
            }
            setCommandAt(last, "")
            setShortcutAt(last, 0)
            settings.commandCount = last
        }
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
        lockGridYPosition: true,
        centerHighlightButtons: true,

        thumbnailWidthGridUnits: 16,
        thumbnailHeightInput: "16:10",
        maxGridAspectRatioInput: "21:9",
        gridWidthFraction: 0.9,
        gridHeightFraction: 0.8,

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
        dumpSortKeys: false,

        shortcutPin: Qt.Key_D,
        shortcutKeepAbove: Qt.Key_A,
        shortcutKeepBelow: Qt.Key_B,
        shortcutFullscreen: Qt.Key_F,
        shortcutNoBorder: Qt.Key_T,
        shortcutIncognito: Qt.Key_I,
        shortcutDemandsAttention: Qt.Key_N,
        shortcutShaded: Qt.Key_S,
        shortcutTransparency: Qt.Key_O,
        shortcutSkipTaskbar: Qt.Key_Q,
        shortcutSkipSwitcher: 0,
        shortcutSkipPager: 0,
        shortcutMaximize: Qt.Key_PageUp,
        shortcutMaximizeHorizontal: Qt.Key_End,
        shortcutMaximizeVertical: Qt.Key_Home,
        shortcutMinimize: Qt.Key_PageDown,
        shortcutKill: 0,
        shortcutClose: Qt.Key_Delete,
        shortcutCopyPid: Qt.Key_P,
        shortcutCopyMenu: Qt.Key_Space,
        shortcutEdit: Qt.Key_E,
        shortcutSettings: Qt.Key_F2,
        shortcutShortcutsPopup: Qt.Key_F1,

        commandCount: 2,
        commandShortcut0: Qt.Key_0,
        command0: "echo {{' dump(w) }} > /tmp/tgpp_debug.txt && kdialog --textbox /tmp/tgpp_debug.txt --title {{' \"[TG++ Debug] \" + w.caption }} --geometry 480x600 {% close() %}",
        commandShortcut1: Qt.Key_1,
        command1: "{{term}} btop -p 1 -f '!^{{w.pid}}$' {% close() %}",

        placeholders: '"term": "konsole -e"',
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


    // Escape single-quotes for bash shell
    function sq(value) {
        return String(value).replace(/'/g, "'\\''")
    }

    // Escape double-quotes for bash shell
    function dq(value) {
        return String(value).replace(/(["\\$`])/g, "\\$1")
    }

    // Two placeholder forms, matched in one pass so neither can run into the
    // other: both hold a single expression, `{{ ... }}` substituting its value
    // and `{% ... %}` substituting nothing - the latter is for side effects, and
    // several statements go in an immediately-invoked lambda.
    // Both are an outer `{ ... }` around an inner `{ ... }` or `% ... %`, which
    // is what keeps the delimiters from being mixed: `{{ ... %}` and `{% ... }}`
    // are not matches at all.
    function expandPlaceholders(template, w) {
        const re = /\{(?:\{(['"]?)([\s\S]*?)\}|%([\s\S]*?)%)\}/g
        const expanded = String(template).replace(re, (match, sigil, expr, stmt) => {
            const isStatement = stmt !== undefined
            const body = isStatement ? stmt : expr;
            try {
                var value = eval("(function() { with (settings.placeholderDict()) { return " + body + " } })")()
            } catch (e) {
                const placeholder = "{" + (isStatement ? "%" : "{") + sigil + " " + body + " " + (isStatement ? "%" : "}") + "}"
                //console.warn("Thumbnail Grid ++: failed to evaluate placeholder (in custom command): ", placeholder, " - ", e)
                //executableSource.connectSource("kdialog --title '[TG++ ERROR]' --error 'Failed to evaluate placeholder (in custom command):\n" + sq(placeholder) + "\n\n" + sq(e) + "'")
                const error = "Failed to evaluate placeholder (in custom command):\n\t" + e +
                    "\n\n=== Placeholder ===\n" + placeholder +
                    "\n\n=== Unexpanded command===\n" + template +
                    "\n\n=== Traceback ===\n\t" + e + "\n" + e.stack;
                showError(error, "Cannot expand placeholder in custom command")
                return ""
            }
            if (isStatement) return ""
            if (sigil === "'") return sigil + sq(value) + sigil
            if (sigil === '"') return sigil + dq(value) + sigil
            return String(value)
        })
        return expanded
    }

    function showMessage(message, title, tag) {
        tag = tag || "message"
        const path = "/tmp/tgpp_message.txt"
        const taggedTitle = "[TG++ " + tag + "] " + title
        const command = `echo '${sq(message)}' > '${path}' && ` +
            `kdialog --textbox '${path}' --title '${taggedTitle}' --geometry 480x600`
        executableSource.connectSource(command)
    }

    function showError(message, title) {
        showMessage(message, title, "ERROR")
        tabBox.close()
    }

    function runCustomCommand(index, w) {
        const command = settings.commandAt(index)
        if (!command || !w) return
        let finalCommand = expandPlaceholders(command, w);
        if (!finalCommand) return
        
        // Max command length that works seems to be around 130k, likely MAX_ARG_STRLEN = 32 pages = 131072 bytes
        const maxLength = 130000;
        if (finalCommand.length >= maxLength) {
            const error = "Expanded custom command length " + finalCommand.length + " > " + maxLength + " max!" +
                "\n\n=== Unexpanded ===\n" + command +
                "\n\n=== Expanded (first " + maxLength + " chars) ===\n" + finalCommand.slice(0, maxLength)
            showError(error, "Cannot run custom command")
            return
        }

        executableSource.connectSource(finalCommand)
    }

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

    // Keeps exactly one settings host open: the popup while the switcher is on
    // screen (a real window would stack behind KWin's overlay), the standalone
    // window once the switcher is gone. Same split as editPopup/editWindowLoader.
    //
    // The standalone window is a PopupWindowLoader, which is what keeps
    // keyboard input working there; see that file. The panel's state (search
    // text, scroll position) is handed over in whichever direction we move.
    function updateSettingsHost() {
        const wantPopup = showPreview && wrapper.visible
        const wantWindow = showPreview && !wrapper.visible
            && (!isPreview || settings.showSettingsAfterPreview)

        // Carry the panel's state across, in whichever direction we are going.
        let handover = null
        if (!wantPopup && settingsPopup.opened)
            handover = settingsPopup.stateForTransfer()
        if (!wantWindow && settingsWindowLoader.active)
            handover = settingsWindowLoader.contentItem.stateForTransfer()

        // The new host opens before the old one closes: closing a host reports
        // the panel as closed, and that only means the user is done with it if
        // no other host has it by then.
        // The panel sets `focus: true`, so opening hands it the keyboard.
        if (wantPopup && !settingsPopup.opened) {
            if (handover)
                settingsPopup.adoptState(handover)
            settingsPopup.open()
        }
        if (wantWindow && !settingsWindowLoader.active)
            settingsWindowLoader.open(handover)

        if (!wantPopup && settingsPopup.opened)
            settingsPopup.close()
        if (!wantWindow && settingsWindowLoader.active)
            settingsWindowLoader.close()
    }

    // Screen rect minus the panels, for placing the standalone settings
    // window. screenGeometry is the full screen and stays right for the
    // fullscreen switcher overlay. Falls back to it if KWin gives us nothing.
    readonly property var workArea: KWin.Workspace?.clientArea(
                                        KWin.Workspace.PlacementArea,
                                        KWin.Workspace.activeScreen,
                                        KWin.Workspace.currentDesktop)
                                    || tabBox.screenGeometry

    onShowPreviewChanged: {
        updateSettingsHost()
        if (!showPreview)
            refocusGrid()
    }

    // Hand the keyboard back to the grid. Every popup and standalone window
    // here takes focus while it is up, and closing one leaves it nowhere -
    // dialogMainItem is the FocusScope all the switcher's key handling hangs
    // off, so without this the shortcuts stay dead even across a reopen.
    function refocusGrid() {
        if (wrapper.visible)
            dialogMainItem.forceActiveFocus()
    }

    // Activate the currently active window through the model.
    // Essentially a no-op, but there does not seem to be a built-in way to do this?
    function close() {
        if (isPreview) {
            wrapper.close();
            return;
        }
        const active = KWin.Workspace?.activeWindow
        if (active) {
            // WIdRole from clientmodel.h (Qt::UserRole + 5)
            const windowIdRole = Qt.UserRole + 5
            for (let i = 0; i < model.rowCount(); i++) {
                if (model.data(model.index(i, 0), windowIdRole) === active.internalId) {
                    model.activate(i)
                    return;
                }
            }
        }
        // Failed to find the window index, activate the first one
        model.activate(0);
    }

    function dump(obj, skipFunctions, maxDepth, _depth) {
        const indentLevel = "    "
        skipFunctions = skipFunctions || true
        maxDepth = maxDepth || 4
        _depth = _depth || 0
        const _indent = indentLevel.repeat(_depth)

        if (_depth >= maxDepth) {
            console.warn("Object too deep, not dumping: " + String(obj));
            return "";
        }

        let keys = Object.keys(obj)
        if (settings.dumpSortKeys) keys.sort()
        
        let lines = []
        if (_depth === 0) lines.push("# " + obj)

        for (let key of keys) {
            let v = obj[key]
            if (skipFunctions && typeof v === "function") {
                continue
            }

            let use_jsonstr = false 
            let jsonstr = ""
            if (_depth > 0) {
                try {
                    jsonstr = JSON.stringify(v)
                } catch (e) {
                    jsonstr = "# [ERROR] " + e
                    use_jsonstr = true
                }
            }

            let str = ""
            if (!use_jsonstr && v !== null && typeof v === "object") {
                str = dump(v, skipFunctions, maxDepth, _depth + 1)
            }
            if (!str) use_jsonstr = true;

            if (use_jsonstr) {
                lines.push(_indent + key + ": " + jsonstr + (jsonstr === "{}" ? "  # " + v : ""))
            } else {
                lines.push(_indent + key + ":")
                lines.push(_indent + indentLevel + "# " + v)
                lines.push(str)
            }
        }
        return lines.join("\n")
    }

    Window {
        id: wrapper
        visible: tabBox.visible
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint

        onVisibleChanged: {
            dialogMainItem.lockedColumns = 0
            dialogMainItem.lockedY = -1
            // Latch after the model has populated for this invocation.
            if (visible && settings.lockGridWidth)
                Qt.callLater(() => dialogMainItem.lockedColumns = dialogMainItem.columns)
            if (visible && settings.lockGridYPosition)
                Qt.callLater(() => dialogMainItem.lockedY = wnd.y)
            // The settings panel follows the switcher between its two hosts.
            tabBox.updateSettingsHost()
            if (visible)
                Qt.callLater(tabBox.refocusGrid)
        }
        color: "transparent"
        width: tabBox.screenGeometry.width
        height: tabBox.screenGeometry.height

        MouseArea {
            anchors.fill: parent
            onClicked: tabBox.close()
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
            PlasmaComponents3.ToolTip.text: "Settings [" + KeyUtils.keyName(settings.shortcutSettings) + "]"
            PlasmaComponents3.ToolTip.visible: hovered
            PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        Item {
            id: wnd
            anchors.horizontalCenter: parent.horizontalCenter
            y: {
                if (settings.lockGridYPosition && dialogMainItem.lockedY >= 0) {
                    let maxY = wrapper.height - wnd.height
                    return Math.max(0, Math.min(dialogMainItem.lockedY, maxY))
                }
                return Math.max(0, (wrapper.height - wnd.height) / 2)
            }
            
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
                    // No transitions: `opened` is only true once the enter
                    // transition has finished, and the handovers below key off
                    // it. With animations slow enough, toggling the switcher
                    // mid-transition would otherwise skip a handover and lose
                    // the edit session.
                    enter: null
                    exit: null
                    screenW: tabBox.screenGeometry.width
                    screenH: tabBox.screenGeometry.height
                    repaintTrick: sharedRepaintTrick
                    shortcutEditKey: settings.shortcutEdit
                    onClosed: tabBox.refocusGrid()
                }

                ShortcutsPopup {
                    id: shortcutsPopup
                    // Parented to the fullscreen overlay rather than the grid
                    // box, so its position is in screen coordinates and it can
                    // sit against the right screen edge.
                    parent: wrapper.contentItem
                    cfg: settings
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
                    return cap * settings.gridWidthFraction
                }
                property int maxH: tabBox.screenGeometry.height * settings.gridHeightFraction
                
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
                // Latched on open so the grid doesn't shift vertically when rows
                // are added or removed mid-session. -1 = not latched yet.
                property real lockedY: -1

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
                    return windows.some(w => closeHoldWindow === (w.transientFor?.internalId ?? w.internalId))
                }

                function closeWindowAt(index) {
                    if (index < 0 || tabBox.pendingIndex >= 0) return
                    tabBox.pendingIndex = tabBox.currentIndex
                    tabBox.model.close(index)
                }

                function cancelCloseHold() {
                    closeRepeatTimer.stop()
                    closeReleaseTimer.stop()
                    closeHoldBlocked = false
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
                    const gap = closeHoldBlocked ? closeReleaseTimer.interval
                                                 : closeRepeatTimer.interval
                    return (closeHoldArmed || closeHoldBlocked)
                        && sinceLast <= gap
                }

                // A hold whose window went away is over, but the key is still
                // down and its repeats keep arriving. Without this the next
                // repeat would read as a fresh press and close whatever got
                // selected in the meantime, marching through the switcher.
                // Further repeats are swallowed until they stop, i.e. until the
                // key is actually released.
                property bool closeHoldBlocked: false

                Timer {
                    id: closeReleaseTimer
                    interval: dialogMainItem.nextRepeatInterval
                    onTriggered: dialogMainItem.closeHoldBlocked = false
                }

                function blockUntilCloseReleased() {
                    closeHoldBlocked = true
                    closeReleaseTimer.restart()
                }

                function beginCloseHold() {
                    const win = currentWindow()
                    // org.kde.kwin.killer dialog is a transient for the unresponsive window.
                    const target = win?.transientFor ?? win
                    closeHoldPid = target?.pid ?? 0
                    closeHoldWindow = target?.internalId ?? null
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

                // Index of the custom-command slot bound to `key`, or -1. Slots with
                // no shortcut (0) or an empty command never match.
                function customCommandSlot(key) {
                    if (!key) return -1
                    for (var i = 0; i < settings.commandCount; ++i) {
                        if (settings.shortcutAt(i) === key && settings.commandAt(i))
                            return i
                    }
                    return -1
                }

                function handleSpecialKeys(key) {
                    const idx = tabBox.model.index(tabBox.currentIndex, 0)
                    const window = currentWindow()

                    if (key === settings.shortcutMaximize) {
                        if (window) { const isMax = window.frameGeometry.width >= tabBox.screenGeometry.width - 1; window.setMaximize(!isMax, !isMax) }
                    } else if (key === settings.shortcutMinimize) {
                        if (window) window.minimized = !window.minimized;
                    } else if (key === settings.shortcutMaximizeVertical) {
                        if (window) { const area = KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window); const isV = window.frameGeometry.height >= area?.height - 1; const isH = window.frameGeometry.width >= area?.width - 1; window.setMaximize(!isV, isH) }
                    } else if (key === settings.shortcutMaximizeHorizontal) {
                        if (window) { const area = KWin.Workspace?.clientArea(KWin.Workspace.MaximizeArea, window); const isV = window.frameGeometry.height >= area?.height - 1; const isH = window.frameGeometry.width >= area?.width - 1; window.setMaximize(isV, !isH) }
                    } else if (key === settings.shortcutFullscreen) {
                        if (window) window.fullScreen = !window.fullScreen
                    } else if (key === settings.shortcutNoBorder) {
                        if (window) window.noBorder = !window.noBorder
                    } else if (key === settings.shortcutKeepAbove) {
                        if (window) window.keepAbove = !window.keepAbove
                    } else if (key === settings.shortcutKeepBelow) {
                        if (window) window.keepBelow = !window.keepBelow
                    } else if (key === settings.shortcutIncognito) {
                        if (window) window.excludeFromCapture = !window.excludeFromCapture
                    } else if (key === settings.shortcutPin) {
                        if (window) window.onAllDesktops = !window.onAllDesktops
                    } else if (key === settings.shortcutDemandsAttention) {
                        if (window) window.demandsAttention = !window.demandsAttention
                    } else if (key === settings.shortcutShaded) {
                        if (window) window.shaded = !window.shaded
                    } else if (key === settings.shortcutTransparency) {
                        if (window) window.opacity = (window.opacity < 0.999) ? 1.0 : settings.opacityWindow
                    } else if (key === settings.shortcutSkipTaskbar) {
                        if (window) window.skipTaskbar = !window.skipTaskbar
                    } else if (key === settings.shortcutSkipPager) {
                        if (window) window.skipPager = !window.skipPager
                    } else if (key === settings.shortcutSkipSwitcher) {
                        if (window) window.skipSwitcher = !window.skipSwitcher
                    } else if (key === settings.shortcutCopyPid) {
                        if (window) {
                            clipboard.content = String(window.pid)
                        }
                    } else if (key === settings.shortcutCopyMenu) {
                        if (window) copyMenu.show(window, currentDelegatePosition())
                    } else if (key === settings.shortcutEdit) {
                        if (window) editPopup.openFor(window, currentDelegatePosition())
                    } else if (key === settings.shortcutSettings) {
                        tabBox.showSettings = !tabBox.showSettings
                    } else if (key === settings.shortcutShortcutsPopup) {
                        shortcutsPopup.toggle()
                    } else if (customCommandSlot(key) >= 0) {
                        tabBox.runCustomCommand(customCommandSlot(key), window)
                    } else {
                        return false;
                    }
                    return true;
                }

                Keys.onPressed: (event) => {
                    if (event.isAutoRepeat) autoRepeatFlagged = true
                    if (event.key === settings.shortcutClose) {
                        event.accepted = true
                        const repeat = isCloseRepeat(event)
                        if (closeHoldBlocked) {
                            // Still held from a hold that already ended.
                            if (repeat) { closeReleaseTimer.restart(); return }
                            closeHoldBlocked = false
                            closeReleaseTimer.stop()
                        }
                        if (repeat && closeHoldArmed) {
                            if (closeHoldTargetAlive()) {
                                continueCloseHold()
                            } else {
                                // It closed as asked; hold ends here and the
                                // key has to come up before another close.
                                cancelCloseHold()
                                blockUntilCloseReleased()
                            }
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
                        shortcutsPopup.close()
                        tabBox.animationFinished = false
                        if (tabBox.visible) {
                            armTimer.start()
                            const editing = editWindowLoader.contentItem
                            if (editWindowLoader.active && editing?.targetWindow) {
                                // Hand the session over by its state, not via
                                // openFor(): that toggles - a second call for
                                // the window already being edited cancels the
                                // edit instead of opening it.
                                const win = editing.targetWindow
                                const state = editing.stateForTransfer()
                                const pos = dialogMainItem.delegatePositionForWindow(win)
                                editWindowLoader.close()
                                editPopup.adoptState(state)
                                if (pos) {
                                    editPopup.x = pos.x
                                    editPopup.y = pos.y
                                }
                                editPopup.open()
                            }
                        } else {
                            if (editPopup.opened && editPopup.targetWindow) {
                                const state = editPopup.stateForTransfer()
                                // Take over where the popup sat. Its x/y are
                                // relative to the item it was declared in, so
                                // ask that item where they land on screen.
                                const at = editPopup.parent.mapToGlobal(editPopup.x,
                                                                        editPopup.y)
                                editWindowLoader.defaultGeometry =
                                    Qt.rect(at.x, at.y,
                                            editPopup.width, editPopup.height)
                                editPopup.close()
                                editWindowLoader.open(state)
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

                                // The model role isn't reachable from outside
                                // the delegate; the buttons need it to notice
                                // the cell being re-bound under a held press.
                                readonly property var cellWindowId: (window?.transientFor?.internalId ?? windowId)

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
                                                    tooltipChecked: "Unpin from all desktops [" + KeyUtils.keyName(settings.shortcutPin) + "]"
                                                    tooltipUnchecked: "Pin to all desktops [" + KeyUtils.keyName(settings.shortcutPin) + "]"
                                                    onToggled: window.onAllDesktops = !window.onAllDesktops
                                                }

                                                // Keep Below Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonKeepBelow
                                                    checked: window?.keepBelow ?? false
                                                    iconName: "window-keep-below-symbolic"
                                                    tooltipChecked: "Remove keep below [" + KeyUtils.keyName(settings.shortcutKeepBelow) + "]"
                                                    tooltipUnchecked: "Keep below [" + KeyUtils.keyName(settings.shortcutKeepBelow) + "]"
                                                    onToggled: window.keepBelow = !window.keepBelow
                                                }

                                                // Keep Above Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonKeepAbove
                                                    checked: window?.keepAbove ?? false
                                                    iconName: "window-keep-above-symbolic"
                                                    tooltipChecked: "Remove keep above [" + KeyUtils.keyName(settings.shortcutKeepAbove) + "]"
                                                    tooltipUnchecked: "Keep above [" + KeyUtils.keyName(settings.shortcutKeepAbove) + "]"
                                                    onToggled: window.keepAbove = !window.keepAbove
                                                }

                                                // Fullscreen Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonFullscreen
                                                    checked: window?.fullScreen ?? false
                                                    supported: window?.fullScreenable ?? false
                                                    iconName: "view-fullscreen-symbolic"
                                                    tooltipChecked: "Exit fullscreen [" + KeyUtils.keyName(settings.shortcutFullscreen) + "]"
                                                    tooltipUnchecked: "Fullscreen [" + KeyUtils.keyName(settings.shortcutFullscreen) + "]"
                                                    onToggled: window.fullScreen = !window.fullScreen
                                                }

                                                // No Border Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonNoBorder
                                                    checked: window?.noBorder ?? false
                                                    iconName: "window-decorations-symbolic"
                                                    tooltipChecked: "Unhide titlebar & frame [" + KeyUtils.keyName(settings.shortcutNoBorder) + "]"
                                                    tooltipUnchecked: "Hide titlebar & frame [" + KeyUtils.keyName(settings.shortcutNoBorder) + "]"
                                                    onToggled: window.noBorder = !window.noBorder
                                                }

                                                // Incognito Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonIncognito
                                                    checked: window?.excludeFromCapture ?? false
                                                    iconName: "view-private-symbolic"
                                                    tooltipChecked: "Disable hide from capture [" + KeyUtils.keyName(settings.shortcutIncognito) + "]"
                                                    tooltipUnchecked: "Hide from screenshots/recordings [" + KeyUtils.keyName(settings.shortcutIncognito) + "]"
                                                    onToggled: window.excludeFromCapture = !window.excludeFromCapture
                                                }

                                                // Demands Attention Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonDemandsAttention
                                                    checked: window?.demandsAttention ?? false
                                                    blink: true
                                                    iconName: "notifications-symbolic"
                                                    tooltipChecked: "Remove attention demand [" + KeyUtils.keyName(settings.shortcutDemandsAttention) + "]"
                                                    tooltipUnchecked: "Demand attention [" + KeyUtils.keyName(settings.shortcutDemandsAttention) + "]"
                                                    onToggled: window.demandsAttention = !window.demandsAttention
                                                }

                                                // Shaded Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonShaded
                                                    checked: window?.shaded ?? false
                                                    supported: window?.shadeable ?? false
                                                    iconName: "window-shade-symbolic"
                                                    tooltipChecked: "Unshade [" + KeyUtils.keyName(settings.shortcutShaded) + "]"
                                                    tooltipUnchecked: "Shade [" + KeyUtils.keyName(settings.shortcutShaded) + "]"
                                                    onToggled: window.shaded = !window.shaded
                                                }

                                                // Opacity Toggle Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonTransparency
                                                    checked: isTransparent
                                                    iconName: "edit-opacity-symbolic"
                                                    tooltipChecked: "Make opaque [" + KeyUtils.keyName(settings.shortcutTransparency) + "]"
                                                    tooltipUnchecked: "Make transparent [" + KeyUtils.keyName(settings.shortcutTransparency) + "]"
                                                    onToggled: window.opacity = isTransparent ? 1.0 : settings.opacityWindow
                                                }

                                                // Skip Taskbar Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipTaskbar
                                                    checked: window?.skipTaskbar ?? false
                                                    iconName: "view-tasks-all-symbolic"
                                                    tooltipChecked: "Show in taskbar [" + KeyUtils.keyName(settings.shortcutSkipTaskbar) + "]"
                                                    tooltipUnchecked: "Skip taskbar [" + KeyUtils.keyName(settings.shortcutSkipTaskbar) + "]"
                                                    onToggled: window.skipTaskbar = !window.skipTaskbar
                                                }

                                                // Skip Switcher Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipSwitcher
                                                    checked: window?.skipSwitcher ?? false
                                                    iconName: "window-list"
                                                    tooltipChecked: "Show in switcher [" + KeyUtils.keyName(settings.shortcutSkipSwitcher) + "]"
                                                    tooltipUnchecked: "Skip switcher [" + KeyUtils.keyName(settings.shortcutSkipSwitcher) + "]"
                                                    onToggled: window.skipSwitcher = !window.skipSwitcher
                                                }

                                                // Skip Pager Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonSkipPager
                                                    checked: window?.skipPager ?? false
                                                    iconName: "window-duplicate-symbolic"
                                                    tooltipChecked: "Show in pager [" + KeyUtils.keyName(settings.shortcutSkipPager) + "]"
                                                    tooltipUnchecked: "Skip pager [" + KeyUtils.keyName(settings.shortcutSkipPager) + "]"
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
                                                    checked: (window?.transientFor ?? window)?.unresponsive ?? false
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
                                                    tooltipUnchecked: holdEnabled ? "Close [" + KeyUtils.keyName(settings.shortcutClose) + "]\nHold to kill" : "Close [" + KeyUtils.keyName(settings.shortcutClose) + "]"
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
                                                    tooltipChecked: "Unmaximize [" + KeyUtils.keyName(settings.shortcutMaximize) + "]"
                                                    tooltipUnchecked: "Maximize [" + KeyUtils.keyName(settings.shortcutMaximize) + "]"
                                                    onToggled: if (window) window.setMaximize(!isMaximized, !isMaximized)
                                                }

                                                // Maximize Horizontal Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonMaximizeHorizontal
                                                    checked: isMaximizedHorizontal
                                                    supported: maximizable
                                                    iconName: "transform-move-horizontal-symbolic"
                                                    tooltipChecked: "Unmaximize horizontally [" + KeyUtils.keyName(settings.shortcutMaximizeHorizontal) + "]"
                                                    tooltipUnchecked: "Maximize horizontally [" + KeyUtils.keyName(settings.shortcutMaximizeHorizontal) + "]"
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
                                                    tooltipChecked: "Unmaximize vertically [" + KeyUtils.keyName(settings.shortcutMaximizeVertical) + "]"
                                                    tooltipUnchecked: "Maximize vertically [" + KeyUtils.keyName(settings.shortcutMaximizeVertical) + "]"
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
                                                    tooltipChecked: "Unminimize [" + KeyUtils.keyName(settings.shortcutMinimize) + "]"
                                                    tooltipUnchecked: "Minimize [" + KeyUtils.keyName(settings.shortcutMinimize) + "]"
                                                    onToggled: window.minimized = !window.minimized
                                                }

                                                // Debug Button
                                                WindowButton {
                                                    cell: cell
                                                    mode: settings.buttonDebug && settings.commandCount > 0
                                                        ? tabBox.buttonModeOnHover : 0
                                                    iconName: "info-symbolic"
                                                    tooltipUnchecked: "Run custom command 0 ["
                                                        + KeyUtils.keyName(settings.shortcutAt(0)) + "]"
                                                    onToggled: tabBox.runCustomCommand(0, window)
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
            // As with editPopup: updateSettingsHost() keys off `opened`.
            enter: null
            exit: null

            cfg: settings
            defaults: tabBox.settingsDefaults
            effectModeModel: tabBox.effectModeModel
            buttonModeModel: tabBox.buttonModeModel
            isPreview: tabBox.isPreview
            toFractionString: tabBox.toFractionString
            maxGridAspectRatio: dialogMainItem.maxGridAspectRatioValue

            x: 0
            y: 0
            // Left screen edge, ending above the settings button so that stays
            // clickable. Dragging and resizing overwrite these (breaking the
            // x/y bindings), so every open resets the lot - the geometry also
            // has to follow the current screen resolution.
            function resetGeometry() {
                x = 0
                y = 0
                width = Kirigami.Units.gridUnit * 46
                height = wrapper.height - settingsButton.height
                         - Kirigami.Units.largeSpacing * 2
            }

            onVisibleChanged: if (visible) resetGeometry()

            onResetPosition: resetGeometry()
            onClosed: {
                if (!settingsWindowLoader.active)
                    tabBox.showSettings = false
                tabBox.refocusGrid()
            }
        }
    }

    // The same panel once the switcher is gone, so settings opened during
    // alt-tab stay open and editable afterwards. See PopupWindowLoader for why
    // the window is built and rebuilt rather than just shown.
    PopupWindowLoader {
        id: settingsWindowLoader
        objectName: "settingsWindow"
        repaintTrick: sharedRepaintTrick
        windowTitle: "TG++ Settings - " + settings.category
        minimumWidth: Kirigami.Units.gridUnit * 34
        minimumHeight: Kirigami.Units.gridUnit * 20
        // Left edge of the work area, full work-area height. Unlike the
        // switcher overlay - which is deliberately fullscreen - this is an
        // ordinary window, so it keeps clear of the panels.
        defaultGeometry: Qt.rect(tabBox.workArea.x, tabBox.workArea.y,
                                 Kirigami.Units.gridUnit * 46,
                                 tabBox.workArea.height)

        onClosed: {
            tabBox.showSettings = false
            tabBox.refocusGrid()
        }

        content: Component {
            SettingsPanel {
                // The loader's window draws the title bar and resize grip.
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

                onResetPosition: settingsWindowLoader.resetGeometry()
                onClosed: settingsWindowLoader.requestClose()
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
    }

    // The geometry editor once the switcher is gone, mirroring the settings
    // panel's popup/window split. Qt.Popup (via PopupWindowLoader) so KWin
    // keeps delivering keyboard events to the spin boxes.
    PopupWindowLoader {
        id: editWindowLoader
        objectName: "editWindow"
        repaintTrick: sharedRepaintTrick
        windowTitle: editWindowLoader.contentItem?.targetWindow
                     ? ("[TG++ Edit] " + editWindowLoader.contentItem.targetWindow.caption)
                     : "[TG++ Edit]"
        minimumWidth: Kirigami.Units.gridUnit * 24
        minimumHeight: Kirigami.Units.gridUnit * 14
        // Overwritten with the popup's place on screen whenever the switcher
        // hands the session over; this is only the fallback for a window
        // opened without a popup to take over from.
        defaultGeometry: Qt.rect(tabBox.workArea.x
                                 + (tabBox.workArea.width - Kirigami.Units.gridUnit * 32) / 2,
                                 tabBox.workArea.y
                                 + (tabBox.workArea.height - Kirigami.Units.gridUnit * 18) / 2,
                                 Kirigami.Units.gridUnit * 32,
                                 Kirigami.Units.gridUnit * 18)

        onClosed: tabBox.refocusGrid()

        // Open the editor for `win`, taking over from the in-switcher popup.
        function openFor(win, origGeo, origOpacity) {
            const g = win.frameGeometry
            const orig = origGeo || g
            editWindowLoader.open({
                targetWindow: win,
                original: {
                    x: orig.x, y: orig.y,
                    width: orig.width, height: orig.height,
                    opacity: Math.round((origOpacity ?? (win.opacity ?? 1.0)) * 100)
                },
                current: {
                    x: g.x, y: g.y, width: g.width, height: g.height,
                    opacity: Math.round((win.opacity ?? 1.0) * 100)
                }
            })
        }

        content: Component {
            EditPopup {
                // The loader's window draws the title bar, so the panel needs
                // neither its own heading nor a background of its own.
                showHeaderLabel: false
                background: null
                windowHosted: true
                x: 0
                y: 0
                width: parent.width
                height: parent.height
                screenW: tabBox.screenGeometry.width
                screenH: tabBox.screenGeometry.height
                repaintTrick: sharedRepaintTrick
                shortcutEditKey: settings.shortcutEdit
                onClosed: editWindowLoader.requestClose()
            }
        }
    }

    // One per plugin, shared by everything that moves a window; see
    // RepaintTrick.qml. Must stay declared *after* the switcher's own `wrapper`
    // window: KWin takes the first Window it finds here as the switcher
    // itself, and this one is transparent and empty.
    RepaintTrick {
        id: sharedRepaintTrick
    }
}
