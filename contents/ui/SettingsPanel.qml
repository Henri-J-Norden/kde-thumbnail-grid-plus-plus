/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2024 Antigravity <antigravity@google.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

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
    // False in the standalone-window host, where the window frame already
    // provides a title bar, dragging and resizing.
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

    readonly property real minimumPanelWidth: Kirigami.Units.gridUnit * 34
    readonly property real minimumPanelHeight: Kirigami.Units.gridUnit * 20

    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: root.showChrome ? Kirigami.Theme.textColor : "transparent"
        border.width: 1
        radius: root.showChrome ? 6 : 0
        opacity: root.showChrome ? 0.97 : 1.0
    }

    // Carries the sidebar/search state when main.qml moves the panel between
    // its popup and standalone-window hosts.
    function adoptStateFrom(other) {
        root.searchText = other.searchText
        _pendingScrollY = other.scrollContentY
        _adoptingState = true
    }

    // Scroll position to restore after the Flickable is laid out.
    property real _pendingScrollY: 0
    property bool _adoptingState: false

    onOpened: {
        if (_adoptingState)
            Qt.callLater(() => {
                settingsScroll.contentY = _pendingScrollY
                _adoptingState = false
            })
        else
            Qt.callLater(() => root.scrollToCategory("buttons"))
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

    // Mirrors the Flickable's contentY so adoptStateFrom can copy it.
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
        { id: "grid",       name: "Grid & layout",      glyph: "▦", count: 3 },
        { id: "thumbnails", name: "Thumbnails",         glyph: "▭", count: 3 },
        { id: "icons",      name: "Icons & labels",     glyph: "◉", count: 2 },
        { id: "minimized",  name: "Minimized windows",  glyph: "▁", count: 10 },
        { id: "buttons",    name: "Window buttons",     glyph: "◧", count: 22 },
        { id: "behaviour",  name: "Behaviour",          glyph: "↹", count: 2 },
        { id: "advanced",   name: "Advanced",           glyph: "⚙", count: 2 }
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
                        && child.searchKey.toLowerCase().indexOf(needle) >= 0)
                    return true
            }
            return false
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
    component SettingRow: RowLayout {
        id: settingRow
        property string searchKey: ""
        // Section.anyMatch reads this; the whole section stays visible when its
        // own title matched, so individual rows must not filter themselves out.
        visible: root.searchText.length === 0
                 || parent.titleMatch
                 || searchKey.toLowerCase().indexOf(root.searchText.toLowerCase()) >= 0
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
    }

    // A label with a "?" superscript and a hover tooltip, as used throughout.
    component HelpLabel: PlasmaComponents3.Label {
        id: helpLabel
        property string help: ""
        property string plain: ""
        // Emitted when the label itself is clicked, so a label can toggle the
        // check box it belongs to.
        signal labelClicked()
        textFormat: Text.RichText
        text: plain + (help !== "" ? "<sup>?</sup>" : "")
        ToolTip.text: help
        ToolTip.visible: help !== "" && maHelp.containsMouse
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
            if (event.key === Qt.Key_F2 || event.key === Qt.Key_Escape) {
                root.close()
                event.accepted = true
            }
        }

        // Stand-in title bar for the popup host. The standalone window has a
        // real one, so this and the resize grip below turn off there.
        Rectangle {
            id: titleBar
            visible: root.showChrome
            height: visible ? implicitTitleHeight : 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            color: Kirigami.Theme.alternateBackgroundColor

            readonly property real implicitTitleHeight: titleLabel.implicitHeight + Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                id: titleLabel
                anchors.centerIn: parent
                text: "Thumbnail Grid ++ — " + root.cfg.category + " profile"
                font.bold: true
            }

            DragHandler {
                target: null
                property real startX: 0
                property real startY: 0
                onActiveChanged: if (active) {
                    startX = root.x
                    startY = root.y
                }
                onActiveTranslationChanged: if (active) {
                    root.x = startX + activeTranslation.x
                    root.y = startY + activeTranslation.y
                }
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

                    PlasmaComponents3.TextField {
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

                            enabled: root.searchText.length === 0
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
                                    text: catDelegate.modelData.count
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
                              : "Changes apply live. Restart KWin to apply them to a fresh session."
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
                spacing: Kirigami.Units.smallSpacing

                Flickable {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: settingsColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar { active: true }

                    ColumnLayout {
                        id: settingsColumn
                        width: settingsScroll.width - settingsScroll.ScrollBar.vertical.width - Kirigami.Units.smallSpacing
                        spacing: 0

                        // ---- Grid & layout -------------------------------
                        Section {
                            id: gridSection
                            cat: "grid"
                            title: "Grid & layout"
                            description: "How the grid of thumbnails is sized and placed on screen."

                            SettingRow {
                                searchKey: "max grid aspect ratio ultrawide"
                                HelpLabel {
                                    plain: "Max grid aspect ratio"
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
                                PlasmaComponents3.TextField {
                                    text: root.cfg.maxGridAspectRatioInput
                                    onTextEdited: root.cfg.maxGridAspectRatioInput = text
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
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
                                    help: "Keep the number of columns fixed while the task switcher is open, so the grid doesn't reflow horizontally when windows are opened or closed. Still widens if the grid would otherwise overflow the screen vertically."
                                    onLabelClicked: cbLockGridWidth.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "background opacity dim"
                                PlasmaComponents3.Label {
                                    text: "Background opacity"
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
                        }

                        // ---- Thumbnails ----------------------------------
                        Section {
                            id: thumbnailsSection
                            cat: "thumbnails"
                            title: "Thumbnails"
                            description: "The size and appearance of each window's thumbnail."

                            SettingRow {
                                searchKey: "thumbnail width grid units size"
                                PlasmaComponents3.Label {
                                    text: "Thumbnail width"
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
                                searchKey: "thumbnail height aspect ratio"
                                PlasmaComponents3.Label {
                                    text: "Thumbnail height"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.TextField {
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
                                PlasmaComponents3.Label {
                                    text: "Thumbnail opacity"
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
                                PlasmaComponents3.Label {
                                    text: "Icon size"
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
                                    help: "When not hovered/selected, move status buttons (normally on the left) and action buttons (normally on the right) towards the center of the thumbnail."
                                    onLabelClicked: cbInvertButtons.toggle()
                                }
                            }

                            SettingRow {
                                searchKey: "window button size"
                                PlasmaComponents3.Label {
                                    text: "Button size"
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
                                    text: root.cfg.buttonSize.toFixed(1) + "×"
                                    horizontalAlignment: Text.AlignRight
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                                }
                            }

                            SettingRow {
                                searchKey: "window button opacity"
                                PlasmaComponents3.Label {
                                    text: "Button opacity"
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
                                rows: [
                                    { group: "Left — status" },
                                    { label: "Pin", key: "buttonPin" },
                                    { label: "Keep above", key: "buttonKeepAbove" },
                                    { label: "Keep below", key: "buttonKeepBelow" },
                                    { label: "Fullscreen", key: "buttonFullscreen" },
                                    { label: "No titlebar", key: "buttonNoBorder" },
                                    { label: "Incognito", key: "buttonIncognito" },
                                    { label: "Demands attention", key: "buttonDemandsAttention" },
                                    { label: "Shaded", key: "buttonShaded" },
                                    { label: "Transparency", key: "buttonTransparency" },
                                    { label: "Skip taskbar", key: "buttonSkipTaskbar" },
                                    { label: "Skip switcher", key: "buttonSkipSwitcher" },
                                    { label: "Skip pager", key: "buttonSkipPager" },
                                    { group: "Right — actions" },
                                    { label: "Minimize", key: "buttonMinimize" },
                                    { label: "Maximize", key: "buttonMaximize" },
                                    { label: "Maximize horizontally", key: "buttonMaximizeHorizontal" },
                                    { label: "Maximize vertically", key: "buttonMaximizeVertical" },
                                    { label: "Close", key: "buttonClose", boolOnly: true },
                                    { label: "Debug", key: "buttonDebug", boolOnly: true }
                                ]
                                filter: parent.titleMatch ? "" : root.searchText
                                visible: shownRows.length > 0
                                Layout.fillWidth: true
                            }

                            PlasmaComponents3.Label {
                                text: "Close and Debug are on/off only — modes 1–3 and 5 need a window state to reflect."
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                                visible: buttonMatrix.visible
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }

                            SettingRow {
                                searchKey: "window transparency button opacity"
                                visible: root.cfg.buttonTransparency !== 0
                                         && (root.searchText.length === 0
                                             || buttonsSection.titleMatch
                                             || searchKey.toLowerCase().indexOf(root.searchText.toLowerCase()) >= 0)
                                PlasmaComponents3.Label {
                                    text: "Transparency button opacity"
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
                        }

                        // ---- Behaviour -----------------------------------
                        Section {
                            id: behaviourSection
                            cat: "behaviour"
                            title: "Behaviour"
                            description: "How the switcher responds to the mouse."

                            SettingRow {
                                searchKey: "select with mouse hover selection"
                                PlasmaComponents3.CheckBox {
                                    id: cbHoverSelection
                                    checked: root.cfg.hoverSelection
                                    onCheckedChanged: root.cfg.hoverSelection = checked
                                }
                                HelpLabel {
                                    plain: "Select with mouse hover"
                                    help: "Useful when \"Show selected windows\" (in Task Switcher - System Setting) is enabled, " +
                                          "to preview a window by just hovering on it in the grid (with the mouse cursor). \n\n" +
                                          "Note: regardless of this setting, you can always: \n" +
                                          "- Click on a window to switch to it. \n" +
                                          "- Cancel task switching by clicking outside the grid or by pressing [Esc] on the keyboard."
                                    onLabelClicked: cbHoverSelection.toggle()
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
                                    help: "Show a settings button (at the bottom left of the screen), when the task switcher is opened."
                                    onLabelClicked: cbButtonSettings.toggle()
                                }
                            }
                        }

                        // ---- Advanced ------------------------------------
                        Section {
                            id: advancedSection
                            cat: "advanced"
                            title: "Advanced"

                            SettingRow {
                                searchKey: "preview repeat count test"
                                HelpLabel {
                                    plain: "Preview repeat count"
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
                                searchKey: "config file location ini profile"
                                PlasmaComponents3.Label {
                                    text: "Config file"
                                    Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                                }
                                PlasmaComponents3.TextField {
                                    text: root.cfg.location
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    readOnly: true
                                    Layout.fillWidth: true
                                }
                                PlasmaComponents3.TextField {
                                    text: root.cfg.category
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    readOnly: true
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

                Kirigami.Separator { Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: root.changedCount === 0
                              ? "All settings are at their defaults"
                              : root.changedCount + (root.changedCount === 1 ? " setting differs" : " settings differ") + " from defaults"
                        color: Kirigami.Theme.disabledTextColor
                    }
                    Item { Layout.fillWidth: true }
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

        // Resize grip for the popup host; the window frame handles this in the
        // standalone one.
        Item {
            visible: root.showChrome
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

            DragHandler {
                target: null
                property real startW: 0
                property real startH: 0
                onActiveChanged: if (active) {
                    startW = root.width
                    startH = root.height
                }
                onActiveTranslationChanged: if (active) {
                    root.width = Math.max(root.minimumPanelWidth, startW + activeTranslation.x)
                    root.height = Math.max(root.minimumPanelHeight, startH + activeTranslation.y)
                }
            }
        }
    }
}
