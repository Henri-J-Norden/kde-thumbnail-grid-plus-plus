/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2024 Antigravity <antigravity@google.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

/*
 * One window-management button overlaid on a thumbnail.
 *
 * Renders in one of two styles, per the configured mode: "button" (a flat
 * PlasmaComponents3.Button) or "badge" (a round RoundButton with a shadow,
 * marking the state it toggles as active). Only one is instantiated at a time.
 *
 * `cell` points at the thumbnail delegate and supplies the per-cell context
 * (selection, hover, sizing) so call sites don't have to repeat it; the
 * individual properties can still be set directly if needed.
 */
Loader {
    id: root

    // The thumbnail delegate this button belongs to. Must expose isCurrent,
    // hovered, buttonSize and buttonBackgroundOpacity.
    property Item cell: null

    // Visibility mode from settings.buttonX; see buttonModeModel in main.qml.
    property int mode: 0
    // Current state of the window property this button toggles.
    property bool checked: false
    // False for windows that don't support the action (e.g. !maximizable).
    property bool supported: true

    property bool cellSelected: cell ? cell.isCurrent : false
    property bool cellHovered: cell ? cell.hovered : false
    property real buttonSize: cell ? cell.buttonSize : Kirigami.Units.gridUnit
    property real backgroundOpacity: cell ? cell.buttonBackgroundOpacity : 1.0

    property string iconName: ""
    // Optional; replaces iconName while checked and directly hovered.
    property string iconNameChecked: ""
    property string tooltipChecked: ""
    property string tooltipUnchecked: ""
    // Pulse the badge (used for "demands attention").
    property bool blink: false

    signal toggled()

    readonly property string tooltipText: checked ? tooltipChecked : tooltipUnchecked
    // True = render as a badge, false = render as a plain button.
    readonly property bool badge: {
        switch (mode) {
        case 1: case 5: return checked
        case 2: return checked && (cellSelected || cellHovered)
        default: return false
        }
    }
    readonly property bool shown: {
        switch (mode) {
        case 1: case 2: case 3: return checked || cellSelected || cellHovered
        case 4: return cellSelected || cellHovered
        case 5: return checked
        default: return false  // 0 = off
        }
    }

    visible: supported && shown
    active: visible
    sourceComponent: badge ? badgeStyle : buttonStyle

    // Declared as explicit property values rather than as children, so there is
    // no ambiguity with Loader's default property.
    property Component badgeStyle: Component {
        PlasmaComponents3.RoundButton {
            icon.name: (root.iconNameChecked && root.checked && hovered)
                       ? root.iconNameChecked : root.iconName
            onClicked: root.toggled()
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            ToolTip.text: root.tooltipText
            ToolTip.visible: hovered
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Kirigami.Theme.neutralTextColor
                shadowBlur: 0.5
            }

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.blink
                NumberAnimation { to: 1.0; duration: 200 }
                NumberAnimation { to: 0.2; duration: 200 }
            }
        }
    }

    property Component buttonStyle: Component {
        PlasmaComponents3.Button {
            icon.name: (root.iconNameChecked && root.checked && hovered)
                       ? root.iconNameChecked : root.iconName
            onClicked: root.toggled()
            background.opacity: root.backgroundOpacity
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            ToolTip.text: root.tooltipText
            ToolTip.visible: hovered
        }
    }
}
