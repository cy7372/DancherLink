import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ItemDelegate {
    property GridView grid

    // CRITICAL: Disable ALL built-in hover and highlight behavior
    hoverEnabled: false
    highlighted: false
    down: false
    checkable: false
    checked: false
    visible: true
    enabled: true
    focus: false
    activeFocusOnTab: false
    activeFocusOnPress: false

    // Our custom highlighted logic - only for keyboard/gamepad navigation
    property bool customHighlighted: grid.activeFocus && grid.currentItem === this

    Keys.onLeftPressed: {
        grid.moveCurrentIndexLeft()
    }
    Keys.onRightPressed: {
        grid.moveCurrentIndexRight()
    }
    Keys.onDownPressed: {
        grid.moveCurrentIndexDown()
    }
    Keys.onUpPressed: {
        grid.moveCurrentIndexUp()
    }
    Keys.onReturnPressed: {
        clicked()
    }
    Keys.onEnterPressed: {
        clicked()
    }
}

