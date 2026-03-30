import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ItemDelegate {
    property GridView grid

    // Disable built-in hover behavior - delegates define their own hover detection
    hoverEnabled: false

    highlighted: grid.activeFocus && grid.currentItem === this

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

