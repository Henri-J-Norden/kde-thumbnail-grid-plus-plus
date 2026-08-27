/*
SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "keyutils.js" as KeyUtils

Popup {
    id: root
    required property var cfg
    required property int customCommandCount
    property int screenW: 1920
    property int screenH: 1080

    modal: false
    closePolicy: Popup.NoAutoClose
    padding: Kirigami.Units.largeSpacing
    width: Kirigami.Units.gridUnit * 18
    height: Math.min(contentItem.implicitHeight + topPadding + bottomPadding,
                     (parent ? parent.height : screenH) - Kirigami.Units.largeSpacing * 2)
    enter: null
    exit: null
    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.textColor
        border.width: 1
        radius: 6
        opacity: 0.95
    }

    readonly property var navShortcuts: [
        { key: "\u2190 \u2192", label: "Previous / next window" },
        { key: "\u2191 \u2193", label: "Row up / row down" },
        { key: "Tab", label: "Cycle forward" },
        { key: "Shift+Tab", label: "Cycle backward" },
        { key: "Enter", label: "Select & close" },
        { key: "Esc", label: "Cancel" },
    ]

    readonly property var actionShortcuts: [
        { label: "Pin to all desktops", key: "shortcutPin" },
        { label: "Keep above", key: "shortcutKeepAbove" },
        { label: "Keep below", key: "shortcutKeepBelow" },
        { label: "Fullscreen", key: "shortcutFullscreen" },
        { label: "No titlebar", key: "shortcutNoBorder" },
        { label: "Incognito", key: "shortcutIncognito" },
        { label: "Demands attention", key: "shortcutDemandsAttention" },
        { label: "Shaded", key: "shortcutShaded" },
        { label: "Transparency", key: "shortcutTransparency" },
        { label: "Skip taskbar", key: "shortcutSkipTaskbar" },
        { label: "Skip switcher", key: "shortcutSkipSwitcher" },
        { label: "Skip pager", key: "shortcutSkipPager" },
        { label: "Maximize", key: "shortcutMaximize" },
        { label: "Maximize horizontally", key: "shortcutMaximizeHorizontal" },
        { label: "Maximize vertically", key: "shortcutMaximizeVertical" },
        { label: "Minimize", key: "shortcutMinimize" },
        { label: "Close (hold to kill)", key: "shortcutClose" },
    ]

    readonly property var utilityShortcuts: [
        { label: "Copy PID", key: "shortcutCopyPid" },
        { label: "Copy menu", key: "shortcutCopyMenu" },
        { label: "Edit geometry", key: "shortcutEdit" },
        { label: "Settings", key: "shortcutSettings" },
        { label: "Shortcuts (this popup)", key: "shortcutShortcutsPopup" },
    ]

    // Only the custom-command slots that have a command; they have no names of
    // their own, so the command string itself is the label.
    readonly property var customShortcuts: {
        var out = []
        for (var i = 0; i < root.customCommandCount; ++i) {
            if (root.cfg["customCommand" + i])
                out.push({ label: root.cfg["customCommand" + i], key: "shortcutCustom" + i })
        }
        return out
    }

    function showPopup() {
        // x/y are relative to the parent item, and anything outside it is
        // clipped away. The caller parents this to the fullscreen overlay, so
        // the parent's right edge is the screen's right edge.
        const pw = root.parent ? root.parent.width : root.screenW
        const ph = root.parent ? root.parent.height : root.screenH
        root.x = Math.max(0, pw - root.width - Kirigami.Units.largeSpacing)
        root.y = Math.max(0, (ph - root.height) / 2)
        root.open()
    }

    function toggle() {
        if (root.visible) root.close()
        else root.showPopup()
    }

    // Flickable so the list stays reachable when the switcher window is too
    // short to show every row at once.
    contentItem: Flickable {
        contentWidth: width
        contentHeight: shortcutColumn.implicitHeight
        implicitHeight: shortcutColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: shortcutColumn
            width: parent.width
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: "Keyboard Shortcuts"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                Layout.alignment: Qt.AlignHCenter
            }

            // --- Navigation section ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                    PlasmaComponents3.Label {
                        text: "Navigation"
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    model: root.navShortcuts
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label {
                            text: modelData.key
                            font.family: "monospace"
                            font.bold: true
                            color: Kirigami.Theme.highlightColor
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            horizontalAlignment: Text.AlignRight
                        }
                        PlasmaComponents3.Label {
                            text: modelData.label
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // --- Actions section ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                    PlasmaComponents3.Label {
                        text: "Window buttons"
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    model: root.actionShortcuts
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        readonly property string keyText: KeyUtils.keyName(root.cfg[modelData.key])
                        readonly property bool disabled: root.cfg[modelData.key] === 0
                        PlasmaComponents3.Label {
                            text: keyText
                            font.family: "monospace"
                            font.bold: true
                            color: Kirigami.Theme.highlightColor
                            opacity: disabled ? 0.4 : 1.0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            horizontalAlignment: Text.AlignRight
                        }
                        PlasmaComponents3.Label {
                            text: modelData.label
                            Layout.fillWidth: true
                            opacity: disabled ? 0.4 : 1.0
                        }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // --- Tools & Settings section ---
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                    PlasmaComponents3.Label {
                        text: "Tools & Settings"
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    model: root.utilityShortcuts
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        readonly property string keyText: KeyUtils.keyName(root.cfg[modelData.key])
                        readonly property bool disabled: root.cfg[modelData.key] === 0
                        PlasmaComponents3.Label {
                            text: keyText
                            font.family: "monospace"
                            font.bold: true
                            color: Kirigami.Theme.highlightColor
                            opacity: disabled ? 0.4 : 1.0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            horizontalAlignment: Text.AlignRight
                        }
                        PlasmaComponents3.Label {
                            text: modelData.label
                            Layout.fillWidth: true
                            opacity: disabled ? 0.4 : 1.0
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: root.customShortcuts.length > 0
            }

            // --- Custom commands section ----------------------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                visible: root.customShortcuts.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                    PlasmaComponents3.Label {
                        text: "Custom commands"
                        font.bold: true
                        color: Kirigami.Theme.highlightColor
                        Layout.fillWidth: true
                    }
                }

                Repeater {
                    model: root.customShortcuts
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        readonly property string keyText: KeyUtils.keyName(root.cfg[modelData.key])
                        readonly property bool disabled: root.cfg[modelData.key] === 0
                        PlasmaComponents3.Label {
                            text: keyText
                            font.family: "monospace"
                            font.bold: true
                            color: Kirigami.Theme.highlightColor
                            opacity: disabled ? 0.4 : 1.0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            horizontalAlignment: Text.AlignRight
                        }
                        PlasmaComponents3.Label {
                            text: modelData.label
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            opacity: disabled ? 0.4 : 1.0
                        }
                    }
                }
            }
        }
    }
}
