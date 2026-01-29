import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

GridView {
    property int minMargin: 10
    property real availableWidth: (parent.width - 2 * minMargin)
    property int itemsPerRow: availableWidth / cellWidth
    property real horizontalMargin: itemsPerRow < count && availableWidth >= cellWidth ?
                                        (availableWidth % cellWidth) / 2 : minMargin

    function updateMargins() {
        leftMargin = horizontalMargin
        rightMargin = horizontalMargin
    }

    onHorizontalMarginChanged: {
        updateMargins()
    }

    Component.onCompleted: {
        updateMargins()
    }

    Rectangle {
        color: Material.background
        width: parent.width
        height: Math.max(parent.contentHeight, parent.height)
        z: -100
    }

    boundsBehavior: Flickable.OvershootBounds
}

