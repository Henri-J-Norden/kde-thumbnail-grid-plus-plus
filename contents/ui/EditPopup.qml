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
    // The shared RepaintTrick from main.qml; moving a window needs a
    // full-screen repaint or it leaves stale frames behind.
    property var repaintTrick: null
    modal: false
    closePolicy: Popup.CloseOnPressOutside
    padding: 0
    width: Kirigami.Units.gridUnit * 32
    height: Kirigami.Units.gridUnit * 18
    background: Rectangle {
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.textColor
        border.width: 1
        radius: 6
        opacity: 0.95

        DragHandler {
            id: dragger
            enabled: parent.visible
            target: null
            property real startX: 0
            property real startY: 0
            onActiveChanged: if (active) {
                dragger.startX = root.x
                dragger.startY = root.y
            }
            onActiveTranslationChanged: if (active) {
                root.x = dragger.startX + activeTranslation.x
                root.y = dragger.startY + activeTranslation.y
            }
        }
    }

    function openFor(win, pos, origGeo, origOpacity) {
        if (root.visible && root.targetWindow === win) {
            root.cancelGeometry()
            return
        }
        root.targetWindow = win
        root.originalGeometry = origGeo || Qt.rect(win.frameGeometry.x, win.frameGeometry.y, win.frameGeometry.width, win.frameGeometry.height)
        root.originalOpacity = origOpacity ?? (win.opacity ?? 1.0)
        if (pos) {
            root.x = pos.x
            root.y = pos.y
        }
        const g = win.frameGeometry
        geoXSpin.value = g.x
        geoYSpin.value = g.y
        geoWSpin.value = g.width
        geoHSpin.value = g.height
        opacitySpin.value = Math.round((win.opacity ?? 1.0) * 100)
        root.open()
    }

    function applyGeometry() {
        const win = root.targetWindow
        if (!win) return
        win.frameGeometry = Qt.rect(geoXSpin.value, geoYSpin.value, geoWSpin.value, geoHSpin.value)
        root.repaintTrick?.trigger()
    }

    function applyOpacity() {
        const win = root.targetWindow
        if (!win) return
        win.opacity = opacitySpin.value / 100
    }

    function cancelGeometry() {
        const win = root.targetWindow
        if (win) {
            win.frameGeometry = root.originalGeometry
            win.opacity = root.originalOpacity
        }
        root.targetWindow = null
        root.close()
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_E) {
            root.cancelGeometry()
            event.accepted = true
        }
    }
    Keys.onEscapePressed: {
        root.cancelGeometry()
    }

    contentItem: ColumnLayout {
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
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Button {
                text: "Apply"
                onClicked: {
                    root.applyGeometry()
                    root.targetWindow = null
                    root.close()
                }
            }
            PlasmaComponents3.Button {
                text: "Cancel [E]"
                onClicked: root.cancelGeometry()
            }
        }
    }

}
