/*
 KWin - the KDE window manager
 This file is part of the KDE project.

 SPDX-FileCopyrightText: 2024 Antigravity <antigravity@google.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import QtCore
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami

KWin.TabBoxSwitcher {
    id: tabBox

    Settings {
        id: appSettings
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwin_thumbnail_grid_plus.ini"
        property bool hoverSelection: true
        property int thumbnailWidthGridUnits: 16
        property string thumbnailHeightInput: "16:9"
        property int iconSizeIndex: 5
    }

    readonly property bool isPreview: tabBox.automaticallyHide === undefined

    Window {
        id: wnd
        visible: tabBox.visible
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
        color: "transparent"

        // Center on screen logic
        x: tabBox.screenGeometry.x + tabBox.screenGeometry.width * 0.5 - width * 0.5
        y: tabBox.screenGeometry.y + tabBox.screenGeometry.height * 0.5 - height * 0.5
        
        // Main Item Container
        FocusScope {
            id: dialogMainItem
            focus: true
            anchors.fill: parent

            // Opaque backing to match original opaque look
            Rectangle {
                anchors.fill: parent
                // Resize slightly to avoid bleeding out of rounded corners if SVG radius is large
                // But mostly standard radius is fine.
                radius: 6 // common default
                color: Kirigami.Theme.backgroundColor
            }

            // Background for the window (Using standard KSVG for themed look)
            KSvg.FrameSvgItem {
                anchors.fill: parent
                imagePath: "dialogs/background"
            }

            //-- Configuration Constants --
            readonly property var iconSizes: [0, Kirigami.Units.iconSizes.small, Kirigami.Units.iconSizes.smallMedium, Kirigami.Units.iconSizes.medium, Kirigami.Units.iconSizes.large, Kirigami.Units.iconSizes.huge, Kirigami.Units.iconSizes.enormous]
            readonly property int iconSize: iconSizes[appSettings.iconSizeIndex] ?? Kirigami.Units.iconSizes.huge
            readonly property int thumbnailWidth: Kirigami.Units.gridUnit * appSettings.thumbnailWidthGridUnits
            readonly property int thumbnailHeight: {
                const input = (appSettings.thumbnailHeightInput || "").trim();

                // Try aspect ratio "X:Y"
                if (input.includes(":")) {
                    const parts = input.split(":");
                    if (parts.length === 2) {
                        const x = parseFloat(parts[0]);
                        const y = parseFloat(parts[1]);
                        if (!isNaN(x) && !isNaN(y) && x > 0) {
                            return Math.round(thumbnailWidth * (y / x));
                        }
                    }
                }

                // Try plain positive number (gridUnits)
                const num = parseFloat(input);
                if (!isNaN(num) && num > 0) {
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
            property int maxW: tabBox.screenGeometry.width * 0.9
            property int maxH: tabBox.screenGeometry.height * 0.8
            
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
            property int itemCount: repeater.count

            property int columns: {
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
                }
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || 
                    event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    navigate(event.key);
                }
            }

            property bool mouseNavActive: false

            Timer {
                id: armTimer
                interval: Kirigami.Units.veryLongDuration
                onTriggered: dialogMainItem.mouseNavActive = true
            }

            Connections {
                target: tabBox
                function onVisibleChanged() {
                    dialogMainItem.mouseNavActive = false
                    if (tabBox.visible) {
                        armTimer.start()
                    }
                }
            }

            Flow {
                id: flow
                anchors.fill: parent
                
                Repeater {
                    id: repeater
                    model: tabBox.model
                    delegate: Item {
                        width: dialogMainItem.cellWidth
                        height: dialogMainItem.cellHeight
                        
                        readonly property bool isCurrent: index === tabBox.currentIndex

                        //-- Background/Highlight --
                        KSvg.FrameSvgItem {
                            anchors.fill: parent
                            imagePath: "widgets/viewitem"
                            prefix: "hover"
                            visible: isCurrent
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: tabBox.model.activate(index)
                            hoverEnabled: appSettings.hoverSelection
                            onPositionChanged: {
                                if (dialogMainItem.mouseNavActive)
                                    tabBox.currentIndex = index
                            }
                            
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
                                }
                                
                                // Close Button (replicate original positioning)
                                PlasmaComponents3.ToolButton {
                                    id: closeButton
                                    anchors {
                                        right: parent.right
                                        top: parent.top
                                        // Deliberately touch the inner edges of the frame (negate the padding)
                                        rightMargin: -dialogMainItem.cellMargin + Kirigami.Units.smallSpacing
                                        topMargin: -dialogMainItem.cellMargin + Kirigami.Units.smallSpacing
                                    }
                                    visible: model.closeable && (isCurrent || hoverHandler.hovered || closeButton.hovered)
                                    icon.name: "window-close-symbolic"
                                    onClicked: tabBox.model.close(index)
                                }
                                
                                HoverHandler {
                                    id: hoverHandler
                                }

                                // Application Icon Overlay
                                Kirigami.Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: -height/2 
                                    width: dialogMainItem.iconSize
                                    height: width
                                    source: model.icon
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
                                // color: "white" // Removed to use theme default
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
                visible: repeater.count === 0
            }
        }
    
        Window {
            id: settingsWnd
            visible: tabBox.isPreview
            flags: Qt.Tool
            color: "transparent"
            title: "Settings: Thumbnail Grid +"
            onClosing: wnd.close()

            x: tabBox.screenGeometry.x + tabBox.screenGeometry.width * 0.5 - width * 0.5
            y: tabBox.screenGeometry.y
            width: settingsItem.implicitWidth
            height: settingsItem.implicitHeight

            Item {
                id: settingsItem
                implicitWidth: Kirigami.Units.gridUnit * 40
                implicitHeight: settingsContent.implicitHeight + Kirigami.Units.largeSpacing * 2

                Rectangle {
                    anchors.fill: parent
                    color: Kirigami.Theme.backgroundColor
                }

                ColumnLayout {
                    id: settingsContent
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: "NB: Restart KWin (log out and log in again) to apply settings to the real task switcher."
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
                            text: appSettings.location
                            font.family: "monospace"
                            font.italic: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                            readOnly: true
                            Layout.fillWidth: true
                        }
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents3.CheckBox {
                        text: "Hover selection"
                        checked: appSettings.hoverSelection
                        onCheckedChanged: appSettings.hoverSelection = checked
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Thumbnail width:" }
                        PlasmaComponents3.SpinBox {
                            from: 8
                            to: 32
                            value: appSettings.thumbnailWidthGridUnits
                            onValueModified: appSettings.thumbnailWidthGridUnits = value
                        }
                        PlasmaComponents3.Label { text: "grid units" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Thumbnail height:" }
                        PlasmaComponents3.TextField {
                            text: appSettings.thumbnailHeightInput
                            onTextEdited: appSettings.thumbnailHeightInput = text
                        }
                        PlasmaComponents3.Label {
                            text: "e.g. 9 (grid units), 16:9 (aspect ratio), or blank for screen ratio"
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label { text: "Icon size:" }
                        PlasmaComponents3.ComboBox {
                            model: ["None", "Small", "Small-Medium", "Medium", "Large", "Huge", "Enormous"]
                            currentIndex: appSettings.iconSizeIndex
                            onActivated: appSettings.iconSizeIndex = currentIndex
                        }
                    }
                }
            }
        }
    }
}
