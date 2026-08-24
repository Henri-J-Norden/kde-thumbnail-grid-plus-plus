/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
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
    // Emitted once the button has been held down for `holdMs`.
    signal held()

    // Press-and-hold duration in ms for the secondary action; 0 disables it.
    property int holdMs: 0
    readonly property bool holdEnabled: holdMs > 0 && holdSupported
    // Lets a call site withhold the hold action per window (e.g. no usable PID).
    property bool holdSupported: true
    // True while the pointer holds the button down.
    property bool pressedDown: false
    // Set by a call site to show the hold progress for a hold driven from
    // elsewhere (the keyboard), without a pointer press.
    property bool holdExternal: false
    // Milliseconds of that hold already elapsed when it became visible. A
    // keyboard hold is only recognisable once auto-repeat confirms it, so the
    // fill still sweeps the whole button, just over the time actually left.
    property int holdStartedMs: 0
    // Only an external hold arrives part-done; a pointer hold is timed from the
    // press, so it must never inherit the keyboard's head start.
    readonly property int holdElapsedMs: holdExternal ? Math.min(holdStartedMs, holdMs) : 0
    // Epoch ms at which the visible sweep began, for external holds. The button
    // lives in a Repeater delegate and is rebuilt whenever the window list
    // changes, so the fill has to be able to resume where the hold actually is
    // instead of restarting from nothing.
    property double holdExternalStart: 0

    // How long the fill has to cross the button, and how much of that is gone.
    readonly property int holdSweepMs: Math.max(1, holdMs - holdElapsedMs)
    function holdSweepElapsed() {
        if (!holdExternal || holdExternalStart <= 0) return 0
        return Math.max(0, Math.min(holdSweepMs, Date.now() - holdExternalStart))
    }
    readonly property bool holding: holdEnabled && (pressedDown || holdExternal)
    // Set once held() has fired, so the release doesn't also emit toggled().
    property bool holdFired: false
    // The holdExternal equivalent: the external hold has reached its action.
    property bool holdExternalFired: false
    // True from the moment the hold action fires until the hold is let go.
    readonly property bool fired: holding
                                  && (holdExternal ? holdExternalFired : holdFired)

    // internalId of the window this cell currently shows. Delegates are shared:
    // when a row disappears the Repeater re-binds the survivors rather than
    // destroying the one that went, so the button under a held pointer can end
    // up pointing at a different window mid-press. Everything the button does
    // acts on that new window, so a press that outlives its target is dropped.
    readonly property var targetId: cell?.cellWindowId ?? null
    // The id captured when the pointer went down, and whether it still matches.
    property var pressedTargetId: null
    readonly property bool pressedTargetLost:
        pressedDown && pressedTargetId !== null && targetId !== pressedTargetId

    onPressedTargetLostChanged: if (pressedTargetLost) {
        // Cancel the hold and mark the press spent, so the release neither
        // kills nor toggles the window that moved in underneath it.
        holdTimer.stop()
        holdFired = true
    }

    onPressedDownChanged: {
        if (pressedDown) pressedTargetId = targetId
        if (!holdEnabled) return
        if (pressedDown) {
            holdFired = false
            holdTimer.restart()
        } else {
            holdTimer.stop()
        }
    }

    // Called by the styles on release. Swallows the click that ends a hold.
    function activate() {
        // A press whose window went away (or was replaced) is not a click.
        if (pressedTargetLost) {
            holdFired = false
            return
        }
        if (holdFired) {
            holdFired = false
            return
        }
        toggled()
    }

    // Assigned to `data` explicitly: Loader's default property is
    // sourceComponent, so a plain child would be taken as the component.
    data: [
        Timer {
            id: holdTimer
            interval: root.holdMs
            onTriggered: {
                root.holdFired = true
                root.held()
            }
        }
    ]

    // The styles are destroyed when the button hides; drop any half-done hold
    // with them so a stale pressedDown can't leave the indicator stuck.
    onActiveChanged: if (!active) {
        pressedDown = false
        holdFired = false
        pressedTargetId = null
    }

    // Fills the entire button from bottom to top over `holdMs`; when the
    // action fires the fill dims and the button flashes once, so the moment
    // it actually happened is visible rather than just "full, still holding".
    property Component holdIndicator: Component {
        Item {
            clip: true

            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                color: Kirigami.Theme.negativeTextColor
                visible: root.holding && opacity > 0
                // Fades away with the flash: once the action has fired there is
                // nothing left counting down, so nothing should stay red.
                opacity: root.fired ? 0.0 : 0.5
                height: 0

                NumberAnimation {
                    id: fillAnimation
                    target: fill
                    property: "height"
                    from: (fill.parent ? fill.parent.height : 0)
                          * (root.holdSweepElapsed() / root.holdSweepMs)
                    to: fill.parent ? fill.parent.height : 0
                    duration: root.holdSweepMs - root.holdSweepElapsed()
                    running: root.holding && !root.fired
                }

                Connections {
                    target: root
                    function onHoldingChanged() {
                        if (!root.holding) fill.height = 0
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Kirigami.Units.longDuration * 2
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                id: flash
                anchors.fill: parent
                radius: height / 4
                color: Kirigami.Theme.negativeTextColor
                opacity: 0
                visible: opacity > 0
            }

            NumberAnimation {
                id: flashAnimation
                target: flash
                property: "opacity"
                from: 0.85
                to: 0
                duration: Kirigami.Units.longDuration * 2
                easing.type: Easing.OutCubic
            }

            Connections {
                target: root
                function onFiredChanged() {
                    if (root.fired) flashAnimation.restart()
                }
            }
        }
    }

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
            onClicked: root.activate()
            onDownChanged: root.pressedDown = down
            // The grid holds the keyboard focus; a press must not take it away,
            // or arrow/Tab navigation dies after the first click.
            focusPolicy: Qt.NoFocus
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            ToolTip.text: root.tooltipText
            ToolTip.visible: hovered

            Loader {
                anchors.fill: parent
                sourceComponent: root.holdEnabled ? root.holdIndicator : null
            }

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
            onClicked: root.activate()
            onDownChanged: root.pressedDown = down
            // The grid holds the keyboard focus; a press must not take it away,
            // or arrow/Tab navigation dies after the first click.
            focusPolicy: Qt.NoFocus
            background.opacity: root.backgroundOpacity
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize
            ToolTip.text: root.tooltipText
            ToolTip.visible: hovered

            Loader {
                anchors.fill: parent
                sourceComponent: root.holdEnabled ? root.holdIndicator : null
            }
        }
    }
}
