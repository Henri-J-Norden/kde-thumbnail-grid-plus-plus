/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

// A grid of radio buttons: one row per setting, one column per mode. Replaces a
// stack of identical combo boxes, so every setting and every mode is visible at
// once. Rows address `cfg` by property name, so callers only supply data.
ColumnLayout {
    id: root

    // The Settings object from main.qml.
    required property var cfg
    // Column headers: [{ num: "0", label: "Off", tooltip: "..." }, ...]
    required property var modes
    // Rows, in order: { group: "Heading" } for a separator, otherwise
    // { label, key, boolOnly, help }. `help` is optional; a row that has it
    // gets the same "?" superscript and tooltip as a HelpLabel elsewhere in the
    // panel. A `boolOnly` row stores a plain bool, so only
    // the "off" column and `boolOnMode` apply to it.
    required property var rows
    // Mode index that a `boolOnly` row's `true` maps to.
    property int boolOnMode: 4
    // Case-insensitive substring filter; empty shows every row.
    property string filter: ""
    // When true, an extra column is appended for keyboard shortcut capture.
    property bool showShortcuts: false
    property real shortcutColumnWidth: Kirigami.Units.gridUnit * 4

    // Property-name -> default value, same object as SettingsPanel.defaults.
    // Drives the "changed from default" highlight and the default-column marker.
    property var defaults: ({})

    property real labelWidth: Kirigami.Units.gridUnit * 11

    spacing: 0

    // Rows surviving `filter`. Group headings are kept above their matching
    // rows so context is preserved while filtering.
    readonly property var shownRows: {
        const f = root.filter.trim().toLowerCase()
        if (f.length === 0)
            return root.rows
        const out = []
        let pendingGroup = null
        for (let i = 0; i < root.rows.length; ++i) {
            const r = root.rows[i]
            if (r.group !== undefined) {
                pendingGroup = r
                continue
            }
            if (r.label.toLowerCase().indexOf(f) >= 0
                    || (r.help !== undefined && r.help.toLowerCase().indexOf(f) >= 0)
                    || (r.key !== undefined && r.key.toLowerCase().indexOf(f) >= 0)
                    || (r.shortcutKey !== undefined && r.shortcutKey.toLowerCase().indexOf(f) >= 0)) {
                if (pendingGroup) {
                    out.push(pendingGroup)
                    pendingGroup = null
                }
                out.push(r)
            }
        }
        return out
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Item { Layout.preferredWidth: root.labelWidth }

        Repeater {
            model: root.modes

            ColumnLayout {
                id: header
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignBottom
                spacing: 0

                PlasmaComponents3.Label {
                    text: header.modelData.num
                    font.family: "monospace"
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }
                PlasmaComponents3.Label {
                    text: header.modelData.label
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true

                    ToolTip.text: header.modelData.tooltip ?? ""
                    ToolTip.visible: (header.modelData.tooltip ?? "") !== "" && maHeader.containsMouse
                    MouseArea { id: maHeader; anchors.fill: parent; hoverEnabled: true }
                }
            }
        }

        PlasmaComponents3.Label {
            text: "Shortcut"
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.preferredWidth: root.shortcutColumnWidth
            Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
            visible: root.showShortcuts
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    Repeater {
        model: root.shownRows

        RowLayout {
            id: matrixRow
            required property var modelData
            readonly property bool isGroup: modelData.group !== undefined
            readonly property bool isChanged: !isGroup && modelData.key !== undefined
                && root.defaults[modelData.key] !== undefined
                && root.cfg[modelData.key] !== root.defaults[modelData.key]
            readonly property int defaultMode: !isGroup && modelData.key !== undefined
                && root.defaults[modelData.key] !== undefined
                ? (modelData.boolOnly
                   ? (root.defaults[modelData.key] ? root.boolOnMode : 0)
                   : root.defaults[modelData.key])
                : -1
            readonly property string defaultLabel: defaultMode >= 0
                ? "Default: " + root.modes[defaultMode].num + " " + root.modes[defaultMode].label
                : ""

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.Label {
                readonly property string help: matrixRow.modelData.help ?? ""
                textFormat: Text.RichText
                text: matrixRow.isGroup
                      ? matrixRow.modelData.group
                      : matrixRow.modelData.label + (help !== "" ? "<sup>?</sup>" : "")
                font.bold: matrixRow.isGroup || matrixRow.isChanged
                font.capitalization: matrixRow.isGroup ? Font.AllUppercase : Font.MixedCase
                font.pointSize: matrixRow.isGroup ? Kirigami.Theme.smallFont.pointSize
                                                  : Kirigami.Theme.defaultFont.pointSize
                color: matrixRow.isGroup ? Kirigami.Theme.disabledTextColor
                       : matrixRow.isChanged ? Kirigami.Theme.highlightColor
                       : Kirigami.Theme.textColor
                elide: Text.ElideRight
                Layout.preferredWidth: root.labelWidth
                Layout.topMargin: matrixRow.isGroup ? Kirigami.Units.smallSpacing : 0

                ToolTip.text: {
                    let t = help
                    if (!matrixRow.isGroup && matrixRow.modelData.key !== undefined) {
                        t += (t !== "" ? "\n\n" : "") + "‣ Setting: " + matrixRow.modelData.key
                        if (matrixRow.modelData.shortcutKey)
                            t += ", " + matrixRow.modelData.shortcutKey
                    }

                    if (matrixRow.isChanged)
                        t += (t !== "" ? "\n" : "") + "‣ " + matrixRow.defaultLabel
                    return t
                }
                ToolTip.visible: !matrixRow.isGroup
                    && (matrixRow.modelData.key !== undefined || help !== "")
                    && maRowLabel.containsMouse
                ToolTip.delay: 0
                MouseArea {
                    id: maRowLabel
                    anchors.fill: parent
                    hoverEnabled: true
                }
            }

            Repeater {
                model: matrixRow.isGroup ? [] : root.modes

                Item {
                    id: cell
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: cellRadio.implicitHeight + 6

                    // Columns a bool-only row cannot express are shown but dimmed,
                    // so the grid stays aligned and the gap is self-explanatory.
                    readonly property bool applicable: !matrixRow.modelData.boolOnly
                                                       || index === 0
                                                       || index === root.boolOnMode
                    readonly property int currentValue: matrixRow.modelData.boolOnly
                        ? (root.cfg[matrixRow.modelData.key] ? root.boolOnMode : 0)
                        : root.cfg[matrixRow.modelData.key]

                    PlasmaComponents3.RadioButton {
                        id: cellRadio
                        anchors.horizontalCenter: parent.horizontalCenter
                        enabled: cell.applicable
                        opacity: cell.applicable ? 1 : 0.3
                        onClicked: {
                            const key = matrixRow.modelData.key
                            root.cfg[key] = matrixRow.modelData.boolOnly
                                ? (cell.index === root.boolOnMode)
                                : cell.index
                        }
                    }

                    // Clicking sets `checked` imperatively, which would clobber a
                    // plain binding; a Binding object re-asserts itself afterwards.
                    Binding {
                        target: cellRadio
                        property: "checked"
                        value: cell.currentValue === cell.index
                        restoreMode: Binding.RestoreBindingOrValue
                    }

                    Rectangle {
                        width: 4
                        height: 4
                        radius: 2
                        color: Kirigami.Theme.disabledTextColor
                        visible: matrixRow.defaultMode >= 0 && cell.index === matrixRow.defaultMode
                        anchors.centerIn: cellRadio
                        //readonly property real radius: min(cellRadio.implicitWidth, cellRadio.implicitHeight)
                        anchors.horizontalCenterOffset: cellRadio.implicitWidth * 0.5 - 3
                        anchors.verticalCenterOffset: cellRadio.implicitWidth * 0.5 - 3
                    }
                }
            }

            Item {
                Layout.preferredWidth: root.shortcutColumnWidth
                implicitHeight: keyCapture.implicitHeight
                visible: root.showShortcuts && !matrixRow.isGroup

                KeyCaptureField {
                    id: keyCapture
                    anchors.fill: parent
                    onKeyCaptured: root.cfg[matrixRow.modelData.shortcutKey] = keyCode
                    visible: root.showShortcuts && !matrixRow.isGroup
                                 && matrixRow.modelData.shortcutKey !== undefined
                }

                Binding {
                    target: keyCapture
                    property: "keyCode"
                    value: root.cfg[matrixRow.modelData.shortcutKey] ?? 0
                    restoreMode: Binding.RestoreBindingOrValue
                }
            }
        }
    }
}
