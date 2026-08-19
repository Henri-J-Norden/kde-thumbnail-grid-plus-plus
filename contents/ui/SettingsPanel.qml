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

// The live settings editor shown in the KWin config dialog's preview, and on
// demand via the configure button. Its own FocusScope so that the text fields
// and spin boxes here keep the keyboard without competing with the grid's
// arrow/Home/End handling in main.qml.
FocusScope {
    id: root

    // The Settings object from main.qml; every control here binds two-way to it.
    required property var cfg
    // Label lists for the mode combo boxes, and the switcher's preview flag.
    required property var effectModeModel
    required property var buttonModeModel
    required property bool isPreview
    // tabBox.toFractionString, passed in as a function value.
    required property var toFractionString
    // Already-parsed max grid aspect ratio; the slider shows it, the text field sets it.
    required property real maxGridAspectRatio

    width: settingsItem.implicitWidth
    height: settingsItem.implicitHeight

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_F2) {
            tabBox.showSettings = false
            event.accepted = true
        }
    }

    Item {
        id: settingsItem
        implicitWidth: Kirigami.Units.gridUnit * 60
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
                visible: root.isPreview
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
                    text: root.cfg.location
                    font.family: "monospace"
                    font.italic: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                    readOnly: true
                    Layout.fillWidth: true
                }
                PlasmaComponents3.TextField {
                    text: root.cfg.category
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
                    value: root.cfg.previewRepeatCount
                    stepSize: 1
                    onMoved: root.cfg.previewRepeatCount = Math.round(value)
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: root.cfg.previewRepeatCount
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
                    checked: root.cfg.hoverSelection
                    onCheckedChanged: root.cfg.hoverSelection = checked
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
                    checked: root.cfg.showProtocol
                    onCheckedChanged: root.cfg.showProtocol = checked
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
                    checked: root.cfg.showSettingsButton
                    onCheckedChanged: root.cfg.showSettingsButton = checked
                }
                PlasmaComponents3.Label {
                    textFormat: Text.RichText
                    text: "Settings button<sup>?</sup>"
                    ToolTip.text: "Show a settings button (at the bottom left of the screen), when the task switcher is opened."
                    ToolTip.visible: ma5.containsMouse
                    MouseArea { id: ma5; anchors.fill: parent; hoverEnabled: true; onClicked: cbButtonSettings.toggle() }
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.CheckBox {
                    id: cbLockGridWidth
                    checked: root.cfg.lockGridWidth
                    onCheckedChanged: root.cfg.lockGridWidth = checked
                }
                PlasmaComponents3.Label {
                    textFormat: Text.RichText
                    text: "Lock grid width<sup>?</sup>"
                    ToolTip.text: "Keep the number of columns fixed while the task switcher is open, so the grid doesn't reflow horizontally when windows are opened or closed. Still widens if the grid would otherwise overflow the screen vertically."
                    ToolTip.visible: ma6.containsMouse
                    MouseArea { id: ma6; anchors.fill: parent; hoverEnabled: true; onClicked: cbLockGridWidth.toggle() }
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
                    value: Math.max(0, Math.min(5, root.maxGridAspectRatio))
                    onMoved: root.cfg.maxGridAspectRatioInput = root.toFractionString(value)
                    Layout.fillWidth: true
                }
                PlasmaComponents3.TextField {
                    text: root.cfg.maxGridAspectRatioInput
                    onTextEdited: root.cfg.maxGridAspectRatioInput = text
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
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedIcon
                            onActivated: root.cfg.minimizedIcon = currentIndex
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
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedIconOpacity
                            onActivated: root.cfg.minimizedIconOpacity = currentIndex
                        }
                    }
                    
                    PlasmaComponents3.GroupBox {
                        PlasmaComponents3.Label { text: "Text:"; Layout.fillHeight: true; }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Italics" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedItalics
                            onActivated: root.cfg.minimizedItalics = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Strikethrough" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedStrikethrough
                            onActivated: root.cfg.minimizedStrikethrough = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Underline" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedUnderline
                            onActivated: root.cfg.minimizedUnderline = currentIndex
                        }
                    }

                    PlasmaComponents3.GroupBox {
                        PlasmaComponents3.Label { text: "Thumbnail:" }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Contrast" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedContrast
                            onActivated: root.cfg.minimizedContrast = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Opacity" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedThumbnailOpacity
                            onActivated: root.cfg.minimizedThumbnailOpacity = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Scale" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedThumbnailScale
                            onActivated: root.cfg.minimizedThumbnailScale = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Rotation" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedThumbnailRotation
                            onActivated: root.cfg.minimizedThumbnailRotation = currentIndex
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        PlasmaComponents3.Label { text: "Blur" }
                        PlasmaComponents3.ComboBox {
                            model: root.effectModeModel
                            currentIndex: root.cfg.minimizedBlur
                            onActivated: root.cfg.minimizedBlur = currentIndex
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
                    value: root.cfg.thumbnailWidthGridUnits
                    onValueModified: root.cfg.thumbnailWidthGridUnits = value
                }
                PlasmaComponents3.Label { text: "grid units" }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Label { text: "Icon size:" }
                PlasmaComponents3.ComboBox {
                    model: ["None", "Small", "Small-Medium", "Medium", "Large", "Huge", "Enormous"]
                    currentIndex: root.cfg.iconSizeIndex
                    onActivated: root.cfg.iconSizeIndex = currentIndex
                }
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label { text: "Thumbnail height:" }
                PlasmaComponents3.TextField {
                    text: root.cfg.thumbnailHeightInput
                    onTextEdited: root.cfg.thumbnailHeightInput = text
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
                    value: root.cfg.opacityThumbnail
                    stepSize: 0.01
                    onMoved: root.cfg.opacityThumbnail = value
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(root.cfg.opacityThumbnail * 100) + "%"
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
                    value: root.cfg.opacityBackground
                    stepSize: 0.01
                    onMoved: root.cfg.opacityBackground = value
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(root.cfg.opacityBackground * 100) + "%"
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
                    value: root.cfg.opacityWindowButton
                    stepSize: 0.01
                    onMoved: root.cfg.opacityWindowButton = value
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(root.cfg.opacityWindowButton * 100) + "%"
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
                    value: root.cfg.buttonSize
                    stepSize: 0.1
                    onMoved: root.cfg.buttonSize = value
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: root.cfg.buttonSize.toFixed(1) + "× grid unit"
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
                    ToolTip.text: "Configure when window management buttons appear on each thumbnail, and in which style.\n\n" +
                                  "Two styles are used:\n" +
                                  "- button: the normal flat style.\n" +
                                  "- badge: round, with a shadow, marking the button's state as active.\n\n" +
                                  "\"active\" means the window state the button toggles is on (e.g. the window is already pinned); " +
                                  "\"hover\" means the thumbnail is hovered or selected.\n\n" +
                                  "The number in each mode's name is the value stored in the config file.\n\n" +
                                  "- 0 Off: never shown.\n" +
                                  "- 1 Button on hover, badge when active: always visible while active (as a badge), and on hover (as a button).\n" +
                                  "- 2 Button on hover, badge when active & hovered: same, except an active button only turns into a badge on hover.\n" +
                                  "- 3 Button on hover + when active: always visible while active, and on hover, but never as a badge.\n" +
                                  "- 4 Button on hover: only visible on hover, never as a badge.\n" +
                                  "- 5 Badge when active only: only visible while active, always as a badge."
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
                            checked: root.cfg.centerHighlightButtons
                            onCheckedChanged: root.cfg.centerHighlightButtons = checked
                        }
                    }

                    PlasmaComponents3.GroupBox {
                        PlasmaComponents3.Label { text: "Left:" }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Pin" }
                    PlasmaComponents3.ComboBox {
                        model: root.buttonModeModel
                        currentIndex: root.cfg.buttonPin
                        onActivated: root.cfg.buttonPin = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Keep below" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonKeepBelow
                            onActivated: root.cfg.buttonKeepBelow = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Keep above" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonKeepAbove
                            onActivated: root.cfg.buttonKeepAbove = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Fullscreen" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonFullscreen
                            onActivated: root.cfg.buttonFullscreen = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "No titlebar" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonNoBorder
                            onActivated: root.cfg.buttonNoBorder = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Incognito" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonIncognito
                            onActivated: root.cfg.buttonIncognito = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Demands attention" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonDemandsAttention
                            onActivated: root.cfg.buttonDemandsAttention = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Shaded" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonShaded
                            onActivated: root.cfg.buttonShaded = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Transparency" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonTransparency
                            onActivated: root.cfg.buttonTransparency = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Skip taskbar" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonSkipTaskbar
                            onActivated: root.cfg.buttonSkipTaskbar = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Skip switcher" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonSkipSwitcher
                            onActivated: root.cfg.buttonSkipSwitcher = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Skip pager" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonSkipPager
                            onActivated: root.cfg.buttonSkipPager = currentIndex
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
                            checked: root.cfg.buttonDebug
                            onCheckedChanged: root.cfg.buttonDebug = checked
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Minimize" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonMinimize
                            onActivated: root.cfg.buttonMinimize = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Maximize" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonMaximize
                            onActivated: root.cfg.buttonMaximize = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label { text: "Maximize horizontally" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonMaximizeHorizontal
                            onActivated: root.cfg.buttonMaximizeHorizontal = currentIndex
                        }
                    }   
                    RowLayout {
                        PlasmaComponents3.Label { text: "Maximize vertically" }
                        PlasmaComponents3.ComboBox {
                            model: root.buttonModeModel
                            currentIndex: root.cfg.buttonMaximizeVertical
                            onActivated: root.cfg.buttonMaximizeVertical = currentIndex
                        }
                    }
                    RowLayout {
                        PlasmaComponents3.Label {
                            text: "Close"
                            MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: cbClose.toggle() }
                        }
                        PlasmaComponents3.CheckBox {
                            id: cbClose
                            checked: root.cfg.buttonClose
                            onCheckedChanged: root.cfg.buttonClose = checked
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.cfg.buttonTransparency != 0
                PlasmaComponents3.Label { text: "Window transparency button opacity:" }
                PlasmaComponents3.Slider {
                    from: 0
                    to: 0.99
                    value: root.cfg.opacityWindow
                    stepSize: 0.01
                    onMoved: root.cfg.opacityWindow = value
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Math.round(root.cfg.opacityWindow * 100) + "%"
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
