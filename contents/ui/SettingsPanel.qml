/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons

// The live settings editor. Like EditPopup, this is a Popup so it can be hosted
// two ways: over the switcher while alt-tab is up (where a real window would sit
// behind KWin's own overlay), and inside a standalone window once the switcher
// is gone. main.qml owns both hosts and hands state over between them.
//
// It is placed along the left screen edge at full height and is movable and
// resizable, so it never has to cover the grid it is configuring.
//
// Settings are grouped into categories shown as one scrollable column. The
// sidebar acts as bookmarks that scroll to each section, and the two
// large blocks of identical combo boxes (minimized-window effects, window
// buttons) are radio matrices instead - see SettingsMatrix.qml.
Popup {
    id: root

    // The Settings object from main.qml; every control here binds two-way to it.
    required property var cfg
    // Property-name -> default value, mirroring Settings' initialisers. Drives
    // the "differs from defaults" count and the Restore defaults button.
    required property var defaults
    // Label lists for the mode matrices, and the switcher's preview flag.
    required property var effectModeModel
    required property var buttonModeModel
    required property bool isPreview
    // tabBox.toFractionString, passed in as a function value.
    required property var toFractionString
    // Already-parsed max grid aspect ratio; the slider shows it, the text field sets it.
    required property real maxGridAspectRatio
    // False in the standalone-window host, where PopupWindowLoader's chrome
    // already provides a title bar, dragging and resizing.
    property bool showChrome: true
    // Emitted when the user clicks "Reset position". main.qml handles it
    // differently for the popup host (reset x/y) and the window host (reset
    // the enclosing Window's position to the screen origin).
    signal resetPosition()

    modal: false
    closePolicy: Popup.NoAutoClose
    padding: 0
    focus: true
    width: Kirigami.Units.gridUnit * 46
    height: Kirigami.Units.gridUnit * 40

    Clipboard { id: clipboard }

    readonly property real minimumPanelWidth: Kirigami.Units.gridUnit * 34
    readonly property real minimumPanelHeight: Kirigami.Units.gridUnit * 20

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: root.showChrome ? Kirigami.Theme.textColor : "transparent"
        border.width: 1
        radius: root.showChrome ? 6 : 0
        opacity: root.showChrome ? 0.97 : 1.0
    }

    // Carries the sidebar/search state when the panel moves between its popup
    // and standalone-window hosts, and across the window rebuilds in
    // PopupWindowLoader.
    function stateForTransfer() {
        return { searchText: root.searchText, scrollY: root.scrollContentY }
    }

    function adoptState(state) {
        root.searchText = state.searchText || ""
        _pendingScrollY = state.scrollY || 0
        _adoptingState = true
    }

    // Scroll position to restore after the Flickable is laid out.
    property real _pendingScrollY: 0
    property bool _adoptingState: false

    onOpened: {
        if (_adoptingState) {
            Qt.callLater(() => {
                settingsScroll.contentY = _pendingScrollY
                _adoptingState = false
            })
        } else {
            // Uncomment to always reset scroll position when settings are re-opened?
            //Qt.callLater(() => settingsScroll.contentY = 0)
        }
    }

    property string searchText: ""

    // Which section is currently at the top of the scroll viewport. Drives the
    // sidebar highlight. Empty while searching.
    readonly property string activeCategory: {
        if (root.searchText.length > 0 || !settingsScroll || settingsScroll.contentHeight <= 0)
            return ""
        var best = ""
        for (var i = 0; i < settingsColumn.children.length; ++i) {
            var child = settingsColumn.children[i]
            if (child.cat === undefined) continue
            if (child.y <= settingsScroll.contentY + 1)
                best = child.cat
        }
        return best
    }

    // Mirrors the Flickable's contentY so stateForTransfer can copy it.
    readonly property real scrollContentY: settingsScroll ? settingsScroll.contentY : 0

    function scrollToCategory(catId) {
        for (var i = 0; i < settingsColumn.children.length; ++i) {
            var child = settingsColumn.children[i]
            if (child.cat === catId) {
                var maxScroll = settingsScroll.contentHeight - settingsScroll.height
                settingsScroll.contentY = Math.max(0, Math.min(child.y, Math.max(0, maxScroll)))
                return
            }
        }
    }

    readonly property var categories: [
        { id: "custom",     name: "Custom commands",    glyph: "❯" },
        { id: "grid",       name: "Grid & layout",      glyph: "▦" },
        { id: "thumbnails", name: "Thumbnails",         glyph: "▭" },
        { id: "icons",      name: "Icons & labels",     glyph: "◉" },
        { id: "minimized",  name: "Minimized windows",  glyph: "▁" },
        { id: "buttons",    name: "Window buttons",     glyph: "◧" },
        { id: "shortcuts",  name: "Other shortcuts",    glyph: "⌨" },
        { id: "advanced",   name: "Meta & preview",     glyph: "⚙" }
    ]

    // "0 Off", "1 On (always)", ... -> { num: "0", label: "Off" }.
    function splitModeLabels(model, tooltips) {
        return model.map((entry, i) => {
            const space = entry.indexOf(" ")
            return { num: entry.slice(0, space), label: entry.slice(space + 1),
                     tooltip: tooltips[i] ?? "" }
        })
    }

    // Reading cfg[k] inside a binding registers the dependency, so this
    // re-evaluates whenever any tracked setting changes.
    readonly property int changedCount: {
        let n = 0
        for (const key in root.defaults)
            if (root.cfg[key] !== root.defaults[key])
                ++n
        return n
    }

    function restoreDefaults() {
        for (const key in root.defaults)
            root.cfg[key] = root.defaults[key]
    }

    // Mirrors main.qml's parse of the same setting, to flag a broken value.
    readonly property bool placeholdersValid: {
        try {
            JSON.parse("{" + root.cfg.placeholders + "}")
            return true
        } catch (e) {
            return false
        }
    }

    // Human-readable rendering of a value for tooltips.
    function formatValue(v) {
        if (v === undefined) return ""
        if (typeof v === "boolean") return v ? "on" : "off"
        return String(v).replace(/\n/g, "\\n")
    }

    // Human-readable rendering of a default value for tooltips.
    function formatDefault(key) {
        return root.formatValue(root.defaults[key])
    }

    // "key: default → current" per line, for the footer-label hover tooltip.
    readonly property string changedSettingsText: {
        let lines = []
        let i = 1
        for (const key in root.defaults)
            if (root.cfg[key] !== root.defaults[key]) {
                const currentVal = root.formatValue(root.cfg[key])
                const truncated = currentVal.length > 40 ? currentVal.slice(0, 37) + "..." : currentVal
                lines.push("[" + i++ + "] " + key + ": " + root.formatValue(root.defaults[key])
                           + " → " + truncated)
            }
        return lines.join("\n")
    }

    // A titled block of settings belonging to one category. Rows added by the
    // caller are appended after the heading. While searching, the section shows
    // if its own title matches or any of its rows does.
    component Section: ColumnLayout {
        id: section

        required property string cat
        required property string title
        property string description: ""

        readonly property bool titleMatch:
            root.searchText.length > 0
            && (title + " " + description).toLowerCase().indexOf(root.searchText.toLowerCase()) >= 0

        readonly property bool anyMatch: {
            if (root.searchText.length === 0)
                return true
            if (section.titleMatch)
                return true
            const needle = root.searchText.toLowerCase()
            for (let i = 0; i < section.children.length; ++i) {
                const child = section.children[i]
                if (child.searchKey !== undefined
                        && (child.searchKey.toLowerCase().indexOf(needle) >= 0
                            || (child.cfgKey !== undefined && child.cfgKey !== ""
                                && child.cfgKey.toLowerCase().indexOf(needle) >= 0)))
                    return true
                // SettingsMatrix:
                if (child.shownRows !== undefined && child.shownRows.length > 0)
                    return true
            }
            return false
        }

        readonly property int visibleCount: {
            let n = 0
            const needle = root.searchText.toLowerCase()
            for (let i = 0; i < section.children.length; ++i) {
                const child = section.children[i]
                if (child.searchKey !== undefined) {
                    if (root.searchText.length === 0 || section.titleMatch
                            || child.searchKey.toLowerCase().indexOf(needle) >= 0
                            || (child.cfgKey !== undefined && child.cfgKey !== ""
                                && child.cfgKey.toLowerCase().indexOf(needle) >= 0))
                        n++
                } else if (child.shownRows !== undefined) {
                    for (let j = 0; j < child.shownRows.length; ++j) {
                        if (child.shownRows[j].group === undefined)
                            n++
                    }
                }
            }
            return n
        }

        visible: root.searchText.length === 0 || anyMatch

        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing * 2
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            text: section.title
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.25
            font.bold: true
            Layout.fillWidth: true
        }
        PlasmaComponents3.Label {
            text: section.description
            visible: text !== ""
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }
    }

    // One setting inside a Section. `searchKey` is what the search box matches.
    // `cfgKey` is auto-detected from the HelpLabel child so rows are also
    // searchable by their config property name.
    component SettingRow: RowLayout {
        id: settingRow
        property string searchKey: ""
        readonly property string cfgKey: {
            for (let i = 0; i < settingRow.children.length; ++i) {
                const c = settingRow.children[i]
                if (c.cfgKey !== undefined && c.cfgKey !== "")
                    return c.cfgKey
            }
            return ""
        }
        // Section.anyMatch reads this; the whole section stays visible when its
        // own title matched, so individual rows must not filter themselves out.
        visible: root.searchText.length === 0
                 || parent.titleMatch
                 || searchKey.toLowerCase().indexOf(root.searchText.toLowerCase()) >= 0
                 || cfgKey.toLowerCase().indexOf(root.searchText.toLowerCase()) >= 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
    }

    // A label with a "?" superscript and a hover tooltip, as used throughout.
    component HelpLabel: PlasmaComponents3.Label {
        id: helpLabel
        property string help: ""
        property string plain: ""
        property string cfgKey: ""
        property string defaultDisplay: ""
        readonly property bool isChanged: cfgKey !== ""
            && root.defaults[cfgKey] !== undefined
            && root.cfg[cfgKey] !== root.defaults[cfgKey]
        readonly property string defaultText: defaultDisplay !== ""
            ? defaultDisplay : root.formatDefault(cfgKey)
        // Emitted when the label itself is clicked, so a label can toggle the
        // check box it belongs to.
        signal labelClicked()
        textFormat: Text.RichText
        text: plain + (help !== "" ? "<sup>?</sup>" : "")
        font.bold: isChanged
        color: isChanged ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
        ToolTip.text: {
            let t = help
            if (cfgKey !== "")
                t += (t !== "" ? "\n\n" : "") + "‣ Setting: " + cfgKey
            if (isChanged)
                t += (t !== "" ? "\n" : "") + "‣ Default: " + defaultText
            return t
        }
        ToolTip.visible: (help !== "" || cfgKey !== "" || isChanged) && maHelp.containsMouse
        ToolTip.delay: 0
        MouseArea {
            id: maHelp
            anchors.fill: parent
            hoverEnabled: true
            onClicked: helpLabel.labelClicked()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === root.cfg.shortcutSettings || event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            }
        }

        // Title bar for the popup host. The standalone window gets a real one
        // from PopupWindowLoader, so this and the resize grip below turn off
        // there.
        Rectangle {
            id: titleBar
            visible: root.showChrome
            height: visible ? implicitTitleHeight : 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            // Sit inside the background's border rather than painting over it.
            anchors.leftMargin: root.showChrome ? 1 : 0
            anchors.rightMargin: root.showChrome ? 1 : 0
            anchors.topMargin: root.showChrome ? 1 : 0
            color: Kirigami.Theme.alternateBackgroundColor

            readonly property real implicitTitleHeight: titleLabel.implicitHeight + Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                id: titleLabel
                anchors.centerIn: parent
                text: "TG++ Settings - " + root.cfg.category
                font.bold: true
            }

            PopupWindowDragArea {
                anchors.fill: parent
                target: root
            }
        }

        RowLayout {
            anchors.top: titleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 0

            // ---- Sidebar -------------------------------------------------
            Rectangle {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                Layout.fillHeight: true
                color: Kirigami.Theme.alternateBackgroundColor

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    KwinTextField {
                        id: searchField
                        placeholderText: "Search settings"
                        text: root.searchText
                        onTextEdited: root.searchText = text
                        Layout.fillWidth: true
                    }

                    Repeater {
                        model: root.categories

                        PlasmaComponents3.ItemDelegate {
                            id: catDelegate
                            required property var modelData

                            readonly property var section: {
                                for (let i = 0; i < settingsColumn.children.length; ++i) {
                                    const child = settingsColumn.children[i]
                                    if (child.cat === catDelegate.modelData.id)
                                        return child
                                }
                                return null
                            }

                            enabled: root.searchText.length === 0
                                     || (section && section.visibleCount > 0)
                            opacity: enabled ? 1 : 0.5
                            highlighted: root.activeCategory === catDelegate.modelData.id
                            onClicked: root.scrollToCategory(catDelegate.modelData.id)
                            Layout.fillWidth: true

                            contentItem: RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents3.Label {
                                    text: catDelegate.modelData.glyph
                                    opacity: 0.75
                                    Layout.preferredWidth: Kirigami.Units.gridUnit
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                PlasmaComponents3.Label {
                                    text: catDelegate.modelData.name
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: catDelegate.section ? catDelegate.section.visibleCount : 0
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Kirigami.Separator { Layout.fillWidth: true }

                    PlasmaComponents3.Label {
                        text: root.isPreview
                              ? "Changes apply to the preview live. Restart KWin (log out and back in) to apply them to the real task switcher."
                              : "Changes apply live."
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }

            Kirigami.Separator { Layout.fillHeight: true }

            // ---- Settings pane -------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Kirigami.Units.largeSpacing
                // The scroll area runs to the panel edge so its scrollbar sits
                // flush; the footer row re-adds the margin for itself.
                Layout.rightMargin: 0
                // Never let the settings content force the pane wider than the
                // panel; the Flickable clips whatever does not fit.
                Layout.minimumWidth: 0
                spacing: Kirigami.Units.smallSpacing

                Flickable {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: PlasmaComponents3.ScrollBar { active: true }

                    ColumnLayout {
                        id: settingsColumn
                        width: settingsScroll.width - settingsScroll.ScrollBar.vertical.width - Kirigami.Units.smallSpacing
                        spacing: 0

                        // ---- Custom commands -----------------------------------
                        Section {
                            id: customSection
                            cat: "custom"
                            title: "Custom commands"
                            description: "User-defined shell commands (currently: " + root.cfg.commandCount + ")."

                            PlasmaComponents3.Label {
                                readonly property string url:
                                    "https://github.com/Henri-J-Norden/kde-thumbnail-grid-plus-plus#custom-commands"
                                text: "👉 <a href=\"" + url + "\">Placeholder syntax reference, with command examples</a>"
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                onLinkActivated: link => Qt.openUrlExternally(link)
                                Layout.bottomMargin: Kirigami.Units.smallSpacing
                                HoverHandler {
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            SettingRow {
                                searchKey: "placeholders json variables term terminal add command slot new"
                                // The label column doubles as somewhere to put an
                                // add button that is reachable without scrolling
                                // past every existing slot.
                                ColumnLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                    // The button is wider than the label, and a
                                    // layout never shrinks below a child's
                                    // implicit width unless told to - without
                                    // this the whole column would widen and stop
                                    // lining up with the rows below.
                                    Layout.maximumWidth: Kirigami.Units.gridUnit * 5
                                    Layout.alignment: Qt.AlignTop

                                    HelpLabel {
                                        plain: "Placeholders"
                                        cfgKey: "placeholders"
                                        help: "Extra names the commands below can use, as the body of a JSON "
                                              + "object - the surrounding { } are implied.\n\n"
                                              + "For example, with\n"
                                              + "  \"term\": \"konsole\"\n"
                                              + "a command can say {{ term }} -e htop instead of naming the "
                                              + "terminal in every slot.\n\n"
                                              + "They are the only names a placeholder can use without a prefix."
                                        Layout.fillWidth: true
                                    }
                                    // Sits at the bottom of the label column, so
                                    // it lines up with the end of the text area.
                                    Item { Layout.fillHeight: true }
                                    PlasmaComponents3.Button {
                                        text: "Add"
                                        icon.name: "list-add-symbolic"
                                        ToolTip.text: "Add a command slot at the end"
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 0
                                        onClicked: root.cfg.addCommand()
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                    }
                                }
                                ColumnLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    KwinTextArea {
                                        text: root.cfg.placeholders
                                        onTextChanged: root.cfg.placeholders = text
                                        font.family: "monospace"
                                        wrapMode: TextEdit.NoWrap
                                        placeholderText: "\"name\": \"value\", ..."
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                                    }
                                    PlasmaComponents3.Label {
                                        // The switcher falls back to defining no
                                        // names at all while this is broken, which
                                        // is silent otherwise.
                                        text: "Not valid JSON - no placeholders are defined"
                                        visible: !root.placeholdersValid
                                        color: Kirigami.Theme.negativeTextColor
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // The slots differ only by index, so they are
                            // generated. Repeater parents its delegates to this
                            // Section, so they take part in search like any
                            // hand-written row.
                            Repeater {
                                model: root.cfg.commandCount
                                delegate: SettingRow {
                                    required property int index
                                    searchKey: "custom command " + index + " run shell exec remove delete"
                                    HelpLabel {
                                        plain: "Command " + index
                                        cfgKey: "command" + index
                                        help: (index === 0 ? "This is the command ran by the Debug window button." : "")
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                    }
                                    KeyCaptureField {
                                        id: kcfCustom
                                        keyCode: root.cfg.shortcutAt(index)
                                        onKeyCaptured: root.cfg.setShortcutAt(index, keyCode)
                                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                    }
                                    Binding {
                                        target: kcfCustom
                                        property: "keyCode"
                                        value: root.cfg.shortcutAt(index)
                                        restoreMode: Binding.RestoreBindingOrValue
                                    }
                                    KwinTextField {
                                        text: root.cfg.commandAt(index)
                                        onTextEdited: root.cfg.setCommandAt(index, text)
                                        font.family: "monospace"
                                        placeholderText: "(no command)"
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents3.Button {
                                        icon.name: "list-remove-symbolic"
                                        implicitWidth: implicitHeight
                                        ToolTip.text: "Delete command " + index
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 0
                                        onClicked: root.cfg.removeCommand(index)
                                    }
                                }
                            }

                            SettingRow {
                                searchKey: "add custom command slot new"
                                PlasmaComponents3.Button {
                                    text: "Add"
                                    icon.name: "list-add-symbolic"
                                    ToolTip.text: "Add a command slot at the end"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 0
                                    onClicked: root.cfg.addCommand()
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                }
                            }
                        }

                        // ---- Grid & layout -------------------------------
                        Section {
                            id: gridSection
                            cat: "grid"
                            title: "Grid & layout"
                            description: "How the grid of thumbnails is sized and placed on screen."


                            SettingRow {
                                searchKey: "background opacity dim"
                                HelpLabel {
                                    plain: "Background opacity"
                                    cfgKey: "opacityBackground"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.0
                                    to: 1.0
                                    stepSize: 0.01
                                    value: root.cfg.opacityBackground
                                    onMoved: root.cfg.opacityBackground = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.opacityBackground * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "select with mouse hover selection"
                                PlasmaComponents3.CheckBox {
                                    id: cbHoverSelection
                                    checked: root.cfg.hoverSelection
                                    onCheckedChanged: root.cfg.hoverSelection = checked
                                }
                                HelpLabel {
                                    plain: "Select with mouse hover"
                                    cfgKey: "hoverSelection"
                                    help: "Useful when \"Show selected windows\" (in Task Switcher - System Setting) is enabled, " +
                                          "to preview a window by just hovering on it in the grid (with the mouse cursor). \n\n" +
                                          "Note: regardless of this setting, you can always: \n" +
                                          "- Click on a window to switch to it. \n" +
                                          "- Cancel task switching by clicking outside the grid or by pressing [Esc] on the keyboard."
                                    onLabelClicked: cbHoverSelection.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "hover selection minimum delta dead zone jitter"
                                HelpLabel {
                                    plain: "Hover dead zone"
                                    cfgKey: "hoverSelectionMinDeltaGU"
                                    help: "Minimum distance the mouse must travel (after the switcher animation finishes) " +
                                          "before hover selection activates. Prevents accidental selection from small " +
                                          "mouse jitter when the cursor is already resting on a thumbnail.\n\n" +
                                          "0 disables this (any movement selects immediately).\n\n" +
                                          "Value is in grid units, which scale with your display's DPI setting."
                                    Layout.minimumWidth: Kirigami.Units.gridUnit * 8
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.0
                                    to: 5.0
                                    stepSize: 0.05
                                    value: root.cfg.hoverSelectionMinDeltaGU
                                    onMoved: root.cfg.hoverSelectionMinDeltaGU = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: root.cfg.hoverSelectionMinDeltaGU.toFixed(2) + " GU (" +
                                          Math.round(root.cfg.hoverSelectionMinDeltaGU * Kirigami.Units.gridUnit) + " px)"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                }
                            }

                            SettingRow {
                                searchKey: "max grid aspect ratio ultrawide"
                                HelpLabel {
                                    plain: "Max grid aspect ratio"
                                    cfgKey: "maxGridAspectRatioInput"
                                    help: "Limits how wide the grid of windows can be relative to its height. \n" +
                                          "Useful for ultrawide displays, to prevent the task switcher from becoming too wide. \n\n" +
                                          "E.g. 21:9 means that: \n" +
                                          "- on monitors wider than 21:9, the grid will stay within a central 21:9 rectangle, \n" +
                                          "- on monitors narrower than 21:9, the limit is the width of the monitor. \n\n" +
                                          "Set to 0 for no limit (always uses the width of the monitor as the limit). \n\n" +
                                          "Note: you can test the effect of this setting by increasing \"Preview repeat count\"."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.0
                                    to: 5.0
                                    stepSize: 0.01
                                    value: Math.max(0, Math.min(5, root.maxGridAspectRatio))
                                    onMoved: root.cfg.maxGridAspectRatioInput = root.toFractionString(value)
                                    Layout.fillWidth: true
                                }
                                KwinTextField {
                                    text: root.cfg.maxGridAspectRatioInput
                                    onTextEdited: root.cfg.maxGridAspectRatioInput = text
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                                }
                                PlasmaComponents3.Label {
                                    text: root.maxGridAspectRatio > 0
                                          ? "= " + root.maxGridAspectRatio.toFixed(2)
                                          : "no limit"
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                            }

                            SettingRow {
                                searchKey: "max grid width screen fraction fill"
                                HelpLabel {
                                    plain: "Max grid width"
                                    cfgKey: "gridWidthFraction"
                                    help: "Maximum width the grid can occupy as a fraction of the available screen width (after the max grid aspect ratio is applied). \n\n" +
                                          "Lower values leave more empty space on the sides."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.1
                                    to: 1.0
                                    stepSize: 0.01
                                    value: root.cfg.gridWidthFraction
                                    onMoved: root.cfg.gridWidthFraction = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.gridWidthFraction * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "max grid height screen fraction fill"
                                HelpLabel {
                                    plain: "Max grid height"
                                    cfgKey: "gridHeightFraction"
                                    help: "Maximum height the grid can occupy as a fraction of the screen height (after the max grid aspect ratio is applied). \n\n" +
                                          "This is the primary layout constraint: the column-count algorithm picks the fewest columns that keep all rows within this height. \n\n" +
                                          "Lower values leave more empty space at the top and bottom."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.1
                                    to: 1.0
                                    stepSize: 0.01
                                    value: root.cfg.gridHeightFraction
                                    onMoved: root.cfg.gridHeightFraction = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.gridHeightFraction * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "lock grid width columns reflow"
                                PlasmaComponents3.CheckBox {
                                    id: cbLockGridWidth
                                    checked: root.cfg.lockGridWidth
                                    onCheckedChanged: root.cfg.lockGridWidth = checked
                                }
                                HelpLabel {
                                    plain: "Lock grid width"
                                    cfgKey: "lockGridWidth"
                                    help: "Keep the number of columns fixed while the task switcher is open, so the grid doesn't reflow horizontally when windows are opened or closed. Still widens if the grid would otherwise overflow the screen vertically."
                                    onLabelClicked: cbLockGridWidth.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "lock grid y position vertical stable"
                                PlasmaComponents3.CheckBox {
                                    id: cbLockGridYPosition
                                    checked: root.cfg.lockGridYPosition
                                    onCheckedChanged: root.cfg.lockGridYPosition = checked
                                }
                                HelpLabel {
                                    plain: "Lock grid Y position"
                                    cfgKey: "lockGridYPosition"
                                    help: "Keep the grid's vertical position fixed while the task switcher is open, so the grid doesn't shift up or down when windows are opened or closed and rows are added or removed. Still shifts up if the grid would otherwise overflow the bottom of the screen."
                                    onLabelClicked: cbLockGridYPosition.toggle()
                                }
                            }
                        }

                        // ---- Thumbnails ----------------------------------
                        Section {
                            id: thumbnailsSection
                            cat: "thumbnails"
                            title: "Thumbnails"
                            description: "The size and appearance of each window's thumbnail."

                            SettingRow {
                                searchKey: "thumbnail width grid units size"
                                HelpLabel {
                                    plain: "Thumbnail width"
                                    cfgKey: "thumbnailWidthGridUnits"
                                    defaultDisplay: "16 grid units"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.SpinBox {
                                    from: 8
                                    to: 32
                                    value: root.cfg.thumbnailWidthGridUnits
                                    onValueModified: root.cfg.thumbnailWidthGridUnits = value
                                }
                                PlasmaComponents3.Label { text: "grid units" }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "thumbnail height aspect ratio ultrawide"
                                HelpLabel {
                                    plain: "Thumbnail height"
                                    cfgKey: "thumbnailHeightInput"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KwinTextField {
                                    text: root.cfg.thumbnailHeightInput
                                    onTextEdited: root.cfg.thumbnailHeightInput = text
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                                }
                                PlasmaComponents3.Label {
                                    text: "e.g. 9 (grid units), 16:9 (aspect ratio), or blank for screen ratio"
                                    color: Kirigami.Theme.disabledTextColor
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }

                            SettingRow {
                                searchKey: "thumbnail opacity"
                                HelpLabel {
                                    plain: "Thumbnail opacity"
                                    cfgKey: "opacityThumbnail"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.0
                                    to: 1.0
                                    stepSize: 0.01
                                    value: root.cfg.opacityThumbnail
                                    onMoved: root.cfg.opacityThumbnail = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.opacityThumbnail * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }
                        }

                        // ---- Icons & labels ------------------------------
                        Section {
                            id: iconsSection
                            cat: "icons"
                            title: "Icons & labels"
                            description: "The app icon and caption drawn on each thumbnail."

                            SettingRow {
                                searchKey: "icon size"
                                HelpLabel {
                                    plain: "Icon size"
                                    cfgKey: "iconSizeIndex"
                                    defaultDisplay: "Large"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.ComboBox {
                                    model: ["None", "Small", "Small-Medium", "Medium", "Large", "Huge", "Enormous"]
                                    currentIndex: root.cfg.iconSizeIndex
                                    onActivated: root.cfg.iconSizeIndex = currentIndex
                                }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "show windowing protocol wayland x11"
                                PlasmaComponents3.CheckBox {
                                    id: cbShowProtocol
                                    checked: root.cfg.showProtocol
                                    onCheckedChanged: root.cfg.showProtocol = checked
                                }
                                HelpLabel {
                                    plain: "Show windowing protocol"
                                    cfgKey: "showProtocol"
                                    help: "Display the windowing protocol (Wayland or X11) next to each window's icon."
                                    onLabelClicked: cbShowProtocol.toggle()
                                }
                            }
                        }

                        // ---- Minimized windows ---------------------------
                        Section {
                            id: minimizedSection
                            cat: "minimized"
                            title: "Minimized windows"
                            description: "How windows that are currently minimized are drawn differently."

                            SettingsMatrix {
                                id: effectMatrix
                                property string searchKey: ""

                                cfg: root.cfg
                                defaults: root.defaults
                                modes: root.splitModeLabels(root.effectModeModel, [
                                    "Never applied.",
                                    "Always applied to minimized windows.",
                                    "Applied to minimized windows.",
                                    "Applied unless the thumbnail is hovered.",
                                    "Applied unless the thumbnail is selected."
                                ])
                                rows: [
                                    { group: "Icon & text" },
                                    { label: "Minimized indicator", key: "minimizedIcon" },
                                    { label: "Icon opacity", key: "minimizedIconOpacity" },
                                    { label: "Italics", key: "minimizedItalics" },
                                    { label: "Strikethrough", key: "minimizedStrikethrough" },
                                    { label: "Underline", key: "minimizedUnderline" },
                                    { group: "Thumbnail" },
                                    { label: "Contrast", key: "minimizedContrast" },
                                    { label: "Opacity", key: "minimizedThumbnailOpacity" },
                                    { label: "Scale", key: "minimizedThumbnailScale" },
                                    { label: "Rotation", key: "minimizedThumbnailRotation" },
                                    { label: "Blur", key: "minimizedBlur" }
                                ]
                                // The section already matched by title, so don't
                                // filter its rows down to nothing.
                                filter: parent.titleMatch ? "" : root.searchText
                                visible: shownRows.length > 0
                                Layout.fillWidth: true
                            }
                        }

                        // ---- Window buttons ------------------------------
                        Section {
                            id: buttonsSection
                            cat: "buttons"
                            title: "Window buttons"
                            description: "When each button appears on a thumbnail, and in which style. " +
                                         "\"Button\" is the flat style; \"badge\" is round with a shadow and marks the state as active. " +
                                         "\"Active\" means the window state the button toggles is on (e.g. the window is already pinned); " +
                                         "\"hover\" means the thumbnail is hovered or selected."

                            SettingRow {
                                searchKey: "center highlight buttons"
                                PlasmaComponents3.CheckBox {
                                    id: cbInvertButtons
                                    checked: root.cfg.centerHighlightButtons
                                    onCheckedChanged: root.cfg.centerHighlightButtons = checked
                                }
                                HelpLabel {
                                    plain: "Move buttons toward the centre when not hovered"
                                    cfgKey: "centerHighlightButtons"
                                    help: "When not hovered/selected, move status buttons (normally on the left) and action buttons (normally on the right) towards the center of the thumbnail."
                                    onLabelClicked: cbInvertButtons.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "window button size"
                                HelpLabel {
                                    plain: "Button size"
                                    cfgKey: "buttonSize"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.5
                                    to: 4.0
                                    stepSize: 0.1
                                    value: root.cfg.buttonSize
                                    onMoved: root.cfg.buttonSize = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: root.cfg.buttonSize.toFixed(1) + " GU"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "window button opacity"
                                HelpLabel {
                                    plain: "Button opacity"
                                    cfgKey: "opacityWindowButton"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0.0
                                    to: 1.0
                                    stepSize: 0.01
                                    value: root.cfg.opacityWindowButton
                                    onMoved: root.cfg.opacityWindowButton = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.opacityWindowButton * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingsMatrix {
                                id: buttonMatrix
                                property string searchKey: ""

                                cfg: root.cfg
                                defaults: root.defaults
                                modes: root.splitModeLabels(root.buttonModeModel, [
                                    "Never shown.",
                                    "Always visible while active (as a badge), and on hover (as a button).",
                                    "Same as 1, except an active button only turns into a badge on hover.",
                                    "Always visible while active, and on hover, but never as a badge.",
                                    "Only visible on hover, never as a badge.",
                                    "Only visible while active, always as a badge."
                                ])
                                showShortcuts: true
                                rows: [
                                    { group: "Left — status" },
                                    { label: "Pin", key: "buttonPin", shortcutKey: "shortcutPin" },
                                    { label: "Keep above", key: "buttonKeepAbove", shortcutKey: "shortcutKeepAbove" },
                                    { label: "Keep below", key: "buttonKeepBelow", shortcutKey: "shortcutKeepBelow" },
                                    { label: "Fullscreen", key: "buttonFullscreen", shortcutKey: "shortcutFullscreen" },
                                    { label: "No titlebar", key: "buttonNoBorder", shortcutKey: "shortcutNoBorder" },
                                    { label: "Incognito", key: "buttonIncognito", shortcutKey: "shortcutIncognito" },
                                    { label: "Demands attention", key: "buttonDemandsAttention", shortcutKey: "shortcutDemandsAttention" },
                                    { label: "Shaded", key: "buttonShaded", shortcutKey: "shortcutShaded" },
                                    { label: "Transparency", key: "buttonTransparency", shortcutKey: "shortcutTransparency" },
                                    { label: "Skip taskbar", key: "buttonSkipTaskbar", shortcutKey: "shortcutSkipTaskbar" },
                                    { label: "Skip switcher", key: "buttonSkipSwitcher", shortcutKey: "shortcutSkipSwitcher" },
                                    { label: "Skip pager", key: "buttonSkipPager", shortcutKey: "shortcutSkipPager" },
                                    { group: "Right — actions" },
                                    { label: "Minimize", key: "buttonMinimize", shortcutKey: "shortcutMinimize" },
                                    { label: "Maximize", key: "buttonMaximize", shortcutKey: "shortcutMaximize" },
                                    { label: "Maximize horizontally", key: "buttonMaximizeHorizontal", shortcutKey: "shortcutMaximizeHorizontal" },
                                    { label: "Maximize vertically", key: "buttonMaximizeVertical", shortcutKey: "shortcutMaximizeVertical" },
                                    { label: "Kill (active = unresponsive)", key: "buttonKill", shortcutKey: "shortcutKill" },
                                    { label: "Close (hold to kill)", key: "buttonClose", boolOnly: true, shortcutKey: "shortcutClose" },
                                    { label: "Debug", key: "buttonDebug", boolOnly: true,
                                      help: "Runs the first custom command (see Custom commands below), "
                                            + "which by default dumps the window's properties into a dialog." }
                                ]
                                filter: parent.titleMatch ? "" : root.searchText
                                visible: shownRows.length > 0
                                Layout.fillWidth: true
                            }

                            SettingRow {
                                searchKey: "window transparency button opacity"
                                HelpLabel {
                                    plain: "Transparency button opacity"
                                    cfgKey: "opacityWindow"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 0
                                    to: 0.99
                                    stepSize: 0.01
                                    value: root.cfg.opacityWindow
                                    onMoved: root.cfg.opacityWindow = value
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: Math.round(root.cfg.opacityWindow * 100) + "%"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "close button hold to kill delete key duration press and hold"
                                enabled: root.cfg.buttonClose
                                HelpLabel {
                                    plain: "Hold Close to kill"
                                    cfgKey: "closeHoldMs"
                                    defaultDisplay: "2000 ms"
                                    help: "How long the Close button (or the Delete key) must be held down to kill the window's process instead of asking it to close. A short press still closes normally. Set to 0 to disable hold-to-kill. Windows with no usable process ID (remote X11 clients) always just close.\n\nThe Delete key always closes the moment it is pressed; holding it then escalates to a kill. The Close button closes on release instead, so holding it kills without ever asking the window to close."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.SpinBox {
                                    from: 0
                                    to: 5000
                                    stepSize: 100
                                    value: root.cfg.closeHoldMs
                                    onValueModified: root.cfg.closeHoldMs = value
                                }
                                PlasmaComponents3.Label { text: "ms" }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "kill button grace period sigterm sigkill force quit"
                                enabled: root.cfg.buttonKill !== 0 || root.cfg.closeHoldMs > 0
                                HelpLabel {
                                    plain: "Kill grace period"
                                    cfgKey: "killGraceSeconds"
                                    defaultDisplay: "3 seconds"
                                    help: "How long a kill waits after asking the window's process to quit (SIGTERM) before forcing it (SIGKILL). Longer gives apps like browsers and editors time to save their session; shorter makes an already-frozen window disappear sooner."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.SpinBox {
                                    from: 0
                                    to: 60
                                    value: root.cfg.killGraceSeconds
                                    onValueModified: root.cfg.killGraceSeconds = value
                                }
                                PlasmaComponents3.Label { text: "seconds" }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "dump properties sort keys debug"
                                PlasmaComponents3.CheckBox {
                                    id: cbDumpSortKeys
                                    checked: root.cfg.dumpSortKeys
                                    onCheckedChanged: root.cfg.dumpSortKeys = checked
                                }
                                HelpLabel {
                                    plain: "Sort keys in debug dump output"
                                    cfgKey: "dumpSortKeys"
                                    help: "Sort property keys alphabetically in the output of dump, the property dumper available to custom commands. When off, keys appear in their natural enumeration order."
                                    onLabelClicked: cbDumpSortKeys.toggle()
                                }
                            }
                        }

                        // ---- Other shortcuts ------------------------------------
                        Section {
                            id: shortcutsSection
                            cat: "shortcuts"
                            title: "Other shortcuts"
                            description: "Keyboard shortcuts for actions that are not window buttons."

                            SettingRow {
                                searchKey: "copy pid clipboard"
                                HelpLabel {
                                    plain: "Copy PID"
                                    cfgKey: "shortcutCopyPid"
                                    help: "Copy the selected window's process ID to the clipboard."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KeyCaptureField {
                                    id: kcfCopyPid
                                    onKeyCaptured: root.cfg.shortcutCopyPid = keyCode
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                Binding {
                                    target: kcfCopyPid
                                    property: "keyCode"
                                    value: root.cfg.shortcutCopyPid
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "copy menu window properties"
                                HelpLabel {
                                    plain: "Show/hide copy menu"
                                    cfgKey: "shortcutCopyMenu"
                                    help: "Open the copy menu for the selected window's properties (caption, geometry, etc.)."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KeyCaptureField {
                                    id: kcfCopyMenu
                                    onKeyCaptured: root.cfg.shortcutCopyMenu = keyCode
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                Binding {
                                    target: kcfCopyMenu
                                    property: "keyCode"
                                    value: root.cfg.shortcutCopyMenu
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "edit window geometry popup"
                                HelpLabel {
                                    plain: "Show/hide edit window"
                                    cfgKey: "shortcutEdit"
                                    help: "Open the geometry editor for the selected window."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KeyCaptureField {
                                    id: kcfEdit
                                    onKeyCaptured: root.cfg.shortcutEdit = keyCode
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                Binding {
                                    target: kcfEdit
                                    property: "keyCode"
                                    value: root.cfg.shortcutEdit
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "settings panel configure toggle"
                                HelpLabel {
                                    plain: "Show/hide settings"
                                    cfgKey: "shortcutSettings"
                                    help: "Open or close the settings panel."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KeyCaptureField {
                                    id: kcfSettings
                                    onKeyCaptured: root.cfg.shortcutSettings = keyCode
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                Binding {
                                    target: kcfSettings
                                    property: "keyCode"
                                    value: root.cfg.shortcutSettings
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Item { Layout.fillWidth: true }
                            }

                            SettingRow {
                                searchKey: "shortcuts popup help cheat sheet f1"
                                HelpLabel {
                                    plain: "Shortcuts popup"
                                    cfgKey: "shortcutShortcutsPopup"
                                    help: "Show or hide the on-screen shortcuts cheat sheet."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                KeyCaptureField {
                                    id: kcfShortcutsPopup
                                    onKeyCaptured: root.cfg.shortcutShortcutsPopup = keyCode
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                                }
                                Binding {
                                    target: kcfShortcutsPopup
                                    property: "keyCode"
                                    value: root.cfg.shortcutShortcutsPopup
                                    restoreMode: Binding.RestoreBindingOrValue
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        // ---- Meta & preview ------------------------------------
                        Section {
                            id: advancedSection
                            cat: "advanced"
                            title: "Meta & preview"
                            description: "Settings metadata and options for previewing setting changes."

                            SettingRow {
                                searchKey: "preview repeat count test"
                                HelpLabel {
                                    plain: "Preview repeat count"
                                    cfgKey: "previewRepeatCount"
                                    help: "Duplicate each window this many times in the preview, to test how the grid behaves with many windows."
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Slider {
                                    from: 1
                                    to: 30
                                    stepSize: 1
                                    value: root.cfg.previewRepeatCount
                                    onMoved: root.cfg.previewRepeatCount = Math.round(value)
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Label {
                                    text: root.cfg.previewRepeatCount
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "config file location ini"
                                PlasmaComponents3.Label {
                                    text: "Config file"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Label {
                                    text: root.cfg.location
                                    font.family: "monospace"
                                    font.italic: true
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: Kirigami.Theme.disabledTextColor
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.Button {
                                    icon.name: "edit-copy"
                                    implicitWidth: implicitHeight
                                    ToolTip.text: "Copy file path"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 0
                                    onClicked: {
                                        clipboard.content = root.cfg.location
                                        copiedTimer.restart()
                                    }
                                    PlasmaComponents3.Label {
                                        text: "Copied!"
                                        visible: copiedTimer.running
                                        color: Kirigami.Theme.highlightColor
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        anchors.centerIn: parent
                                        padding: Kirigami.Units.smallSpacing
                                        background: Rectangle {
                                            color: Kirigami.Theme.backgroundColor
                                            border.color: Kirigami.Theme.highlightColor
                                            border.width: 1
                                            radius: 3
                                        }
                                    }
                                    Timer {
                                        id: copiedTimer
                                        interval: 1500
                                        repeat: false
                                    }
                                }
                            }

                            SettingRow {
                                searchKey: "profile category name"
                                PlasmaComponents3.Label {
                                    text: "Profile"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.Label {
                                    text: root.cfg.category
                                    font.family: "monospace"
                                    font.italic: true
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.fillWidth: true
                                }
                            }

                            SettingRow {
                                searchKey: "settings button configure"
                                PlasmaComponents3.CheckBox {
                                    id: cbButtonSettings
                                    checked: root.cfg.showSettingsButton
                                    onCheckedChanged: root.cfg.showSettingsButton = checked
                                }
                                HelpLabel {
                                    plain: "Show settings button"
                                    cfgKey: "showSettingsButton"
                                    help: "Show a settings button (at the bottom left of the screen), when the task switcher is opened."
                                    onLabelClicked: cbButtonSettings.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "show settings window after closing preview"
                                PlasmaComponents3.CheckBox {
                                    id: cbShowSettingsAfterPreview
                                    checked: root.cfg.showSettingsAfterPreview
                                    onCheckedChanged: root.cfg.showSettingsAfterPreview = checked
                                }
                                HelpLabel {
                                    plain: "Show settings after closing preview"
                                    cfgKey: "showSettingsAfterPreview"
                                    help: "Keep the settings panel open in a standalone window after the preview is closed (e.g. by clicking the background or pressing Esc)."
                                    onLabelClicked: cbShowSettingsAfterPreview.toggle()
                                }
                            }
                        }

                        Kirigami.PlaceholderMessage {
                            text: "No settings match \"" + root.searchText + "\""
                            visible: root.searchText.length > 0 && !anySectionVisible
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.gridUnit * 4

                            readonly property bool anySectionVisible: {
                                const siblings = parent.children
                                for (let i = 0; i < siblings.length; ++i)
                                    if (siblings[i].cat !== undefined && siblings[i].visible)
                                        return true
                                return false
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    Layout.rightMargin: Kirigami.Units.largeSpacing
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.rightMargin: Kirigami.Units.largeSpacing * 2
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        id: footerLabel
                        text: root.changedCount === 0
                              ? "All settings are at their defaults"
                              : root.changedCount + (root.changedCount === 1 ? " setting differs" : " settings differ") + " from defaults"
                        color: Kirigami.Theme.disabledTextColor
                        // Takes the slack and gives it up again: at the panel's
                        // minimum width the buttons must still fit.
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        ToolTip {
                            text: root.changedSettingsText
                            visible: root.changedCount > 0 && maFooter.containsMouse
                            delay: 0
                            width: 600
                        }
                        MouseArea {
                            id: maFooter
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                    PlasmaComponents3.Button {
                        text: "Reset position"
                        onClicked: root.resetPosition()
                    }
                    PlasmaComponents3.Button {
                        text: "Restore defaults"
                        enabled: root.changedCount > 0
                        onClicked: root.restoreDefaults()
                    }
                    PlasmaComponents3.Button {
                        text: "Done"
                        onClicked: root.close()
                    }
                }
            }
        }

        // Resize grip for the popup host; PopupWindowLoader draws its own in
        // the standalone window.
        PopupWindowDragArea {
            visible: root.showChrome
            enabled: visible
            target: root
            resize: true
            minimumWidth: root.minimumPanelWidth
            minimumHeight: root.minimumPanelHeight
            width: Kirigami.Units.gridUnit
            height: Kirigami.Units.gridUnit
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            // Three diagonal ticks, drawn rather than themed so there is no
            // dependency on an icon name being present.
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: parent.width - index * (parent.width / 3)
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.4
                    rotation: -45
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: index * 2
                    anchors.verticalCenterOffset: index * 2
                }
            }
        }
    }
}
