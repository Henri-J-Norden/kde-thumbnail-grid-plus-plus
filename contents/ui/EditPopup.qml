/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

Popup {
    id: root
    property var targetWindow: null
    property rect originalGeometry: Qt.rect(0, 0, 0, 0)
    property real originalOpacity: 1.0
    property int screenW: 1920
    property int screenH: 1080
    property bool showHeaderLabel: true
    // True in the standalone-window host. Only there does this popup handle
    // its own keys: inside the switcher, main.qml's grid handler owns the
    // keyboard and routes [E]/Escape here itself, and taking focus would
    // steal keys from it.
    property bool windowHosted: false
    property int shortcutEditKey: Qt.Key_E
    // The shared RepaintTrick from main.qml; moving anything from inside KWin
    // needs a full-screen repaint or it leaves stale frames behind.
    property var repaintTrick: null
    // Set while this popup is the one writing frameGeometry, so the window's
    // own change signal does not echo back into the fields mid-write.
    property bool _writing: false
    modal: false
    focus: root.windowHosted
    // Matches SettingsPanel: a click on the switcher behind should not throw
    // away an edit in progress. Escape, [E] and Cancel still dismiss it.
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: Kirigami.Units.gridUnit * 36
    height: Kirigami.Units.gridUnit * 18
    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.textColor
        border.width: 1
        radius: 6
        opacity: 0.95

        // Drag anywhere on the background, for the popup host. In the window
        // host PopupWindowLoader's title bar does this instead - and there the
        // background is not used at all.
        PopupWindowDragArea {
            anchors.fill: parent
            enabled: parent.visible
            target: root
        }
    }

    // The edit session as plain numbers. Every read/write of the fields goes
    // through this shape, so the five-value tuple is spelled out once per
    // direction instead of once per caller. Opacity is 0-100 here, matching
    // the spinbox; only _writeToWindow converts back to the window's 0-1.
    function _values() {
        return {
            x: geoXSpin.value, y: geoYSpin.value,
            width: geoWSpin.value, height: geoHSpin.value,
            opacity: opacitySpin.value
        }
    }

    function _setValues(v) {
        geoXSpin.value = v.x
        geoYSpin.value = v.y
        geoWSpin.value = v.width
        geoHSpin.value = v.height
        opacitySpin.value = v.opacity
    }

    // The values to go back to on cancel or revert.
    function _originalValues() {
        const g = root.originalGeometry
        return {
            x: g.x, y: g.y,
            width: g.width, height: g.height,
            opacity: Math.round(root.originalOpacity * 100)
        }
    }

    function _windowValues(win) {
        const g = win.frameGeometry
        return {
            x: g.x, y: g.y,
            width: g.width, height: g.height,
            opacity: Math.round((win.opacity ?? 1.0) * 100)
        }
    }

    function _writeToWindow(v) {
        const win = root.targetWindow
        if (!win) return
        root._writing = true
        win.frameGeometry = Qt.rect(v.x, v.y, v.width, v.height)
        win.opacity = v.opacity / 100
        root._writing = false
        root.repaintTrick?.trigger()
    }

    function _syncFromWindow() {
        const win = root.targetWindow
        if (!win || root._writing) return
        root._setValues(root._windowValues(win))
    }

    Connections {
        target: root.visible ? root.targetWindow : null
        function onFrameGeometryChanged() { root._syncFromWindow() }
        function onOpacityChanged() { root._syncFromWindow() }
    }

    function openFor(win, pos, origGeo, origOpacity) {
        if (root.visible && root.targetWindow === win) {
            root.dismiss(true)
            return
        }
        root.targetWindow = win
        root.originalGeometry = origGeo || Qt.rect(win.frameGeometry.x, win.frameGeometry.y, win.frameGeometry.width, win.frameGeometry.height)
        root.originalOpacity = origOpacity ?? (win.opacity ?? 1.0)
        if (pos) {
            root.x = pos.x
            root.y = pos.y
        }
        root._setValues(root._windowValues(win))
        root.open()
    }

    // Carries the whole editing session across a host change or a window
    // rebuild: the window being edited, the values to restore on cancel, and
    // whatever is currently typed into the fields but not yet applied.
    // Both halves are plain numbers: a rect read off a property is a reference
    // into that object, and goes stale when the object it came from is
    // destroyed.
    function stateForTransfer() {
        return {
            targetWindow: root.targetWindow,
            original: root._originalValues(),
            current: root._values()
        }
    }

    // Also the way Apply moves the baseline: adopting a state whose `original`
    // is the values just written makes those the new revert point.
    function adoptState(state) {
        const o = state.original
        root.targetWindow = state.targetWindow
        root.originalGeometry = Qt.rect(o.x, o.y, o.width, o.height)
        root.originalOpacity = o.opacity / 100
        root._setValues(state.current)
    }

    // Kept separate from applyOpacity: the slider handlers drive one axis at a
    // time, and only a geometry change needs the full-screen repaint.
    function applyGeometry() {
        const win = root.targetWindow
        if (!win) return
        root._writing = true
        win.frameGeometry = Qt.rect(geoXSpin.value, geoYSpin.value, geoWSpin.value, geoHSpin.value)
        root._writing = false
        root.repaintTrick?.trigger()
    }

    function applyOpacity() {
        const win = root.targetWindow
        if (!win) return
        root._writing = true
        win.opacity = opacitySpin.value / 100
        root._writing = false
    }

    // The one exit path. revert=true puts the window back the way it was;
    // otherwise the typed values are committed.
    function dismiss(revert) {
        if (revert)
            root._writeToWindow(root._originalValues())
        else
            root.applyGeometry()
        root.targetWindow = null
        root.close()
    }

    contentItem: Item {
        id: content

        focus: root.windowHosted
        Keys.onPressed: (event) => {
            if (event.key === root.shortcutEditKey || event.key === Qt.Key_Escape) {
                root.dismiss(true)
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                text: root.targetWindow ? ("[TG++ Edit] " + root.targetWindow.caption) : "[TG++ Edit]"
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
                visible: root.showHeaderLabel
            }

            PlasmaComponents3.GroupBox {
                Layout.fillWidth: true
                title: "Geometry"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "X"; Layout.preferredWidth: Kirigami.Units.gridUnit; font.bold: true }
                        PlasmaComponents3.Slider {
                            id: geoXSlider
                            from: -root.screenW
                            to: root.screenW * 2
                            stepSize: 1
                            Layout.fillWidth: true
                            onMoved: { geoXSpin.value = Math.round(value); root.applyGeometry() }
                            value: geoXSpin.value
                        }
                        PlasmaComponents3.SpinBox {
                            id: geoXSpin
                            from: -root.screenW
                            to: root.screenW * 2
                            stepSize: 1
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            onValueModified: root.applyGeometry()
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(root.originalGeometry.x)
                            opacity: 0.6
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "Y"; Layout.preferredWidth: Kirigami.Units.gridUnit; font.bold: true }
                        PlasmaComponents3.Slider {
                            id: geoYSlider
                            from: -root.screenH
                            to: root.screenH * 2
                            stepSize: 1
                            Layout.fillWidth: true
                            onMoved: { geoYSpin.value = Math.round(value); root.applyGeometry() }
                            value: geoYSpin.value
                        }
                        PlasmaComponents3.SpinBox {
                            id: geoYSpin
                            from: -root.screenH
                            to: root.screenH * 2
                            stepSize: 1
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            onValueModified: root.applyGeometry()
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(root.originalGeometry.y)
                            opacity: 0.6
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "W"; Layout.preferredWidth: Kirigami.Units.gridUnit; font.bold: true }
                        PlasmaComponents3.Slider {
                            id: geoWSlider
                            from: 1
                            to: root.screenW * 2
                            stepSize: 1
                            Layout.fillWidth: true
                            onMoved: { geoWSpin.value = Math.round(value); root.applyGeometry() }
                            value: geoWSpin.value
                        }
                        PlasmaComponents3.SpinBox {
                            id: geoWSpin
                            from: 1
                            to: root.screenW * 2
                            stepSize: 1
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            onValueModified: root.applyGeometry()
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(root.originalGeometry.width)
                            opacity: 0.6
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        PlasmaComponents3.Label { text: "H"; Layout.preferredWidth: Kirigami.Units.gridUnit; font.bold: true }
                        PlasmaComponents3.Slider {
                            id: geoHSlider
                            from: 1
                            to: root.screenH * 2
                            stepSize: 1
                            Layout.fillWidth: true
                            onMoved: { geoHSpin.value = Math.round(value); root.applyGeometry() }
                            value: geoHSpin.value
                        }
                        PlasmaComponents3.SpinBox {
                            id: geoHSpin
                            from: 1
                            to: root.screenH * 2
                            stepSize: 1
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            onValueModified: root.applyGeometry()
                        }
                        PlasmaComponents3.Label {
                            text: Math.round(root.originalGeometry.height)
                            opacity: 0.6
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                        }
                    }
                }
            }

            PlasmaComponents3.GroupBox {
                Layout.fillWidth: true
                title: "Opacity"

                RowLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Slider {
                        id: opacitySlider
                        from: 0
                        to: 100
                        stepSize: 1
                        Layout.fillWidth: true
                        onMoved: { opacitySpin.value = Math.round(value); root.applyOpacity() }
                        value: opacitySpin.value
                    }
                    PlasmaComponents3.SpinBox {
                        id: opacitySpin
                        from: 0
                        to: 100
                        stepSize: 1
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                        onValueModified: root.applyOpacity()
                    }
                    PlasmaComponents3.Label {
                        text: Math.round(root.originalOpacity * 100)
                        opacity: 0.6
                        horizontalAlignment: Text.AlignRight
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Button {
                    text: "OK"
                    onClicked: root.dismiss(false)
                }
                PlasmaComponents3.Button {
                    text: "Apply"
                    onClicked: {
                        const v = root._values()
                        root._writeToWindow(v)
                        root.adoptState({ targetWindow: root.targetWindow,
                                          original: v, current: v })
                    }
                }
                PlasmaComponents3.Button {
                    text: "Revert"
                    onClicked: {
                        const orig = root._originalValues()
                        root._setValues(orig)
                        root._writeToWindow(orig)
                    }
                }
                PlasmaComponents3.Button {
                    text: "Cancel [E]"
                    onClicked: root.dismiss(true)
                }
            }
        }
    }

}
