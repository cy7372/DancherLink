import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

import "."

ItemDelegate {
    id: delegateRoot
    property GridView grid
    property int cardIndex: -1  // Set by delegate

    // Hover state - tracks whether the card is hovered by mouse
    property bool cardHovered: false

    // Hover state from child buttons (set by buttons when hovered)
    property bool childHovered: false

    // Combined hover state
    property bool isHovered: cardHovered || childHovered

    // Disable built-in hover behavior — we handle it ourselves
    hoverEnabled: false

    // CRITICAL: Use keyboardSelectedIndex instead of currentItem to avoid
    // GridView's automatic currentIndex behavior when using mouse
    highlighted: false
    property bool customHighlighted: grid && grid.keyboardSelectedIndex === cardIndex

    // Background highlight for hover and keyboard selection
    background: Rectangle {
        id: delegateBackground
        width: delegateRoot.width
        height: delegateRoot.height
        color: delegateRoot.isHovered ? AppTheme.backgroundHover :
               (delegateRoot.customHighlighted ? AppTheme.backgroundHighlighted : "transparent")
        radius: AppTheme.borderRadius
        Behavior on color {
            ColorAnimation {
                duration: AppTheme.animationDurationFast
                easing.type: Easing.OutCubic
            }
        }
    }

    // Scale animation for hover effect
    scale: isHovered ? 1.03 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: AppTheme.animationDurationFast
            easing.type: Easing.OutCubic
        }
    }

    // HoverHandler is the correct tool for hover detection.
    // Unlike MouseArea, HoverHandler does NOT consume any mouse events —
    // it purely observes. This means clicks, right-clicks, wheel events,
    // and child MouseAreas all work correctly without interference.
    HoverHandler {
        id: hoverHandler
        onHoveredChanged: {
            delegateRoot.cardHovered = hovered
        }
    }

    // Refresh hover when visibility changes (e.g. navigating back to this page)
    onVisibleChanged: {
        if (visible) {
            refreshHoverTimer.start()
        }
    }

    // Refresh when the parent grid regains active focus
    Connections {
        target: grid
        function onActiveFocusChanged() {
            if (grid && grid.activeFocus) {
                refreshHoverTimer.start()
            }
        }
    }

    // Trigger on Component.onCompleted — onVisibleChanged does NOT fire
    // for newly created delegates (they start with visible: true by default).
    Component.onCompleted: {
        refreshHoverTimer.start()
    }

    // Timer-based hover refresh using QCursor::pos() via C++ helper.
    // Handles the case where a card appears under the cursor without
    // a mouse move event (e.g. page navigation, delegate creation).
    Timer {
        id: refreshHoverTimer
        interval: 200
        onTriggered: {
            if (!delegateRoot.visible) return

            var globalPos = cursorHelper.cursorPos()
            var localPos = delegateRoot.mapFromGlobal(globalPos.x, globalPos.y)
            var isMouseOver = delegateRoot.contains(localPos)

            delegateRoot.cardHovered = isMouseOver
        }
    }
}
