import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.15

ItemDelegate {
    property GridView grid

    highlighted: grid.activeFocus && grid.currentItem === this

    hoverEnabled: true

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

    // Use ItemDelegate's built-in hovered property
    // The content in PcView/AppView is rendered in the contentItem
    // MouseArea is not needed as ItemDelegate handles hover internally
}

