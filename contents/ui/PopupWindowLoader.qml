/*
 SPDX-FileCopyrightText: 2026 Henri J. Norden <55378880+Henri-J-Norden@users.noreply.github.com>
 SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import org.kde.plasma.components 3.0 as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Hosts a Popup in a standalone window that keeps working as a KWin internal
// window.
//
// Windows created from inside KWin only receive keyboard events if they carry
// the Qt.Popup flag, because KWin's PopupInputFilter is what routes keys to
// them. The same filter also dismisses popups on an outside click or focus
// change, and once dismissed a window stops being tracked - it stays on screen
// but goes deaf. There is no API to re-register it.
//
// So on dismissal we refuse the close (the window stays put) and dim it to
// show it is inert; the next click on it builds a replacement, which KWin
// tracks afresh. The two windows overlap: the replacement is up and painted
// before the old one goes, which is what stops the swap from being visible -
// destroying first leaves a gap while the new window is created and mapped,
// and KWin's own vanishing animation would play over it. The hosted content is
// recreated too, so it hands its state over via the optional
// stateForTransfer()/adoptState() pair - anything it does not implement simply
// is not carried over.
//
// A Qt.Popup window carries no decoration, so this also draws the chrome the
// window manager would have provided - title bar, close button, resize grip -
// and hands the content the area below it. Hosted content should therefore
// turn its own popup-mode chrome off.
//
// The caller supplies `content` (a Component whose root is a Popup) and
// `defaultGeometry`, and drives the window with open()/close().
Item {
    id: root

    // A Popup to host. Declare it in the calling file so its bindings still
    // resolve that file's ids; it is created with the window's contentItem as
    // its parent, so `parent.width`/`parent.height` fill the window.
    property Component content

    // Where a freshly opened window goes. Re-read on every open(), so a
    // changed screen resolution or panel layout is picked up.
    property rect defaultGeometry


    property string windowTitle: ""

    // Passed to the chrome's drag areas; see RepaintTrick.
    property var repaintTrick: null

    // Smallest the user can drag the window down to.
    property real minimumWidth: 0
    property real minimumHeight: 0

    // How long the retiring window is kept up behind its replacement: long
    // enough for KWin to have finished animating the new one in.
    property int overlapDuration: Kirigami.Units.veryLongDuration

    // The live window, and the Popup inside it. Both change identity on every
    // rebuild, so read them rather than caching them.
    property var item: null
    readonly property var contentItem: item ? item.hosted : null

    readonly property bool active: item !== null

    // Emitted when the content asked to be closed via requestClose(), never
    // for the silent teardown that close() does.
    signal closed()

    // True while PopupInputFilter has dismissed the window: still visible, no
    // longer receiving keys, waiting for the click that rebuilds it.
    property bool stale: false

    // Geometry the window binds to, so it survives a rebuild.
    property real savedX: 0
    property real savedY: 0
    property real savedWidth: 0
    property real savedHeight: 0

    // State handed to the next content instance, from adoptState()'s caller or
    // from the instance being torn down in reclaimInput().
    property var _pendingState: null

    // The window being retired, still on screen behind its replacement.
    property var _retiring: null

    // Show the window, optionally seeding the content's state (e.g. handing
    // over from another host). Geometry always starts from defaultGeometry:
    // only a rebuild preserves what the user dragged or resized to.
    function open(state) {
        if (active)
            return
        _pendingState = state || null
        seedGeometry()
        item = windowComponent.createObject(root)
    }

    // Tear the window down without reporting it - for handing the content over
    // to another host, where the caller already knows what is happening.
    function close() {
        stale = false
        _pendingState = null
        retireNow()
        if (item) {
            // Cleared before destroying, so that the closed() the content
            // emits on its way out sees no live window - see requestClose().
            const going = item
            item = null
            going.destroy()
        }
    }

    // What the content calls when the user closes it. A Popup also emits
    // closed() as it is destroyed, so tearing the window down reaches here as
    // well; by then there is no live window and there is nothing to report.
    function requestClose() {
        if (!active)
            return
        close()
        root.closed()
    }

    function saveGeometry() {
        savedX = item.x
        savedY = item.y
        savedWidth = item.width
        savedHeight = item.height
    }

    function seedGeometry() {
        savedX = defaultGeometry.x
        savedY = defaultGeometry.y
        savedWidth = defaultGeometry.width
        savedHeight = defaultGeometry.height
    }

    // "Reset position" on a window that is already up: reseed, then mirror onto
    // the live window, whose geometry bindings a drag or resize has broken.
    function resetGeometry() {
        seedGeometry()
        if (item) {
            item.x = savedX
            item.y = savedY
            item.width = savedWidth
            item.height = savedHeight
        }
    }

    // Build a replacement window so KWin tracks it again, carrying the
    // content's state and the window's current geometry across. The old window
    // stays on screen underneath until retireTimer fires.
    function reclaimInput() {
        if (!active)
            return
        stale = false
        _pendingState = contentItem.stateForTransfer ? contentItem.stateForTransfer() : null
        saveGeometry()

        retireNow()
        _retiring = item
        item = windowComponent.createObject(root)
        retireTimer.restart()
    }

    // Keep the retiring window under the live one while both are up: dragging
    // or resizing during the overlap would otherwise slide the live window off
    // the old one, showing it.
    function mirrorToRetiring() {
        if (!_retiring || !item)
            return
        _retiring.x = item.x
        _retiring.y = item.y
        _retiring.width = item.width
        _retiring.height = item.height
    }

    // Drop the retiring window - once its replacement is up and has finished
    // animating in, or early because it has been replaced twice over or the
    // whole thing is closing. It goes transparent first and is destroyed a
    // turn later, so that KWin's animation of it vanishing plays on a window
    // that is already invisible.
    function retireNow() {
        retireTimer.stop()
        if (!_retiring)
            return
        const going = _retiring
        _retiring = null
        going.opacity = 0
        Qt.callLater(() => going.destroy())
    }

    Timer {
        id: retireTimer
        interval: root.overlapDuration
        onTriggered: root.retireNow()
    }

    Component {
        id: windowComponent

        Window {
            id: hostWindow

            // Qt.Popup is what gets us keyboard events; it also means no
            // decoration, so the content draws its own title bar.
            flags: Qt.Popup | Qt.WindowStaysOnTopHint
            color: Kirigami.Theme.backgroundColor
            title: root.windowTitle

            x: root.savedX
            y: root.savedY
            width: root.savedWidth
            height: root.savedHeight

            // Shown from Component.onCompleted once the content exists: a
            // declarative `visible: true` does not map a window created
            // outside the scene.
            visible: false

            property var hosted: null

            onXChanged: root.mirrorToRetiring()
            onYChanged: root.mirrorToRetiring()
            onWidthChanged: root.mirrorToRetiring()
            onHeightChanged: root.mirrorToRetiring()


            // Chrome, and the area left over for the content. The content is a
            // Popup and so draws in the window's overlay, above every item
            // here - which is why it is given its own area to sit in rather
            // than being layered against the chrome, and why the resize grip
            // below has to live in that overlay too.
            Rectangle {
                id: titleBar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: titleLabel.implicitHeight + Kirigami.Units.largeSpacing
                color: Kirigami.Theme.alternateBackgroundColor

                PlasmaComponents3.Label {
                    id: titleLabel
                    anchors.centerIn: parent
                    text: root.windowTitle
                    font.bold: true
                }

                PopupWindowDragArea {
                    anchors.fill: parent
                    target: hostWindow
                    insideTarget: true
                    repaintTrick: root.repaintTrick
                }

                // Sets the title bar off from the content, which otherwise
                // meets it in the same background colour.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.4
                }
            }

            Item {
                id: contentArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: titleBar.bottom
                anchors.bottom: parent.bottom
            }

            // In the overlay, so it stays above the hosted Popup.
            PopupWindowDragArea {
                parent: Overlay.overlay
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Kirigami.Units.gridUnit
                height: Kirigami.Units.gridUnit
                z: 999
                target: hostWindow
                resize: true
                minimumWidth: root.minimumWidth
                minimumHeight: root.minimumHeight
                repaintTrick: root.repaintTrick

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

            Component.onCompleted: {
                hosted = root.content.createObject(contentArea)
                if (hosted) {
                    // The window's dismissal behaviour is the loader's to
                    // decide, not the content's: PopupInputFilter's dismissals
                    // arrive as a window close, which onClosing below refuses,
                    // and the content closing itself underneath that would be
                    // a second, inconsistent way out. Whatever policy the
                    // content uses when hosted in a switcher popup, in here it
                    // stays open until something asks it to go.
                    hosted.closePolicy = Popup.NoAutoClose
                    // Reopened on every rebuild, so its open transition would
                    // play each time.
                    hosted.enter = null
                    hosted.exit = null
                    if (root._pendingState && hosted.adoptState)
                        hosted.adoptState(root._pendingState)
                    if (hosted.open)
                        hosted.open()
                }
                root._pendingState = null
                hostWindow.show()
            }

            onClosing: (close) => {
                // The only closes we get are PopupInputFilter's dismissals -
                // everything else destroys the window outright. Refuse it so
                // the window stays on screen, and mark it inert until the next
                // click rebuilds it. A window being retired gets dismissed too,
                // when its replacement appears; that is not the live window
                // going stale.
                close.accepted = false
                if (hostWindow === root.item)
                    root.stale = true
            }

            // While inert, dim the window and let the first click anywhere on
            // it rebuild instead of reaching the controls. Parented to the
            // popup overlay so it covers the hosted Popup.
            MouseArea {
                parent: Overlay.overlay
                anchors.fill: parent
                z: 1000
                enabled: root.stale && hostWindow === root.item
                visible: enabled
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: root.reclaimInput()

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: 0.3
                }
            }
        }
    }
}
