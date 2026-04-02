import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls.Material 2.15

GridView {
    property int minMargin: 10
    property real availableWidth: parent ? (parent.width - 2 * minMargin) : 0
    property int itemsPerRow: availableWidth > 0 ? Math.floor(availableWidth / cellWidth) : 0
    property real horizontalMargin: {
        if (itemsPerRow <= 0 || availableWidth < cellWidth) {
            return minMargin
        }
        if (itemsPerRow < count) {
            return (availableWidth - (itemsPerRow * cellWidth)) / 2
        }
        return minMargin
    }

    function updateMargins() {
        leftMargin = horizontalMargin
        rightMargin = horizontalMargin
    }

    // Optimize: only update margins when necessary
    onHorizontalMarginChanged: updateMargins()
    onWidthChanged: updateMargins()
    onCountChanged: updateMargins()

    Component.onCompleted: updateMargins()

    // Performance: use a simple background instead of a separate Rectangle item
    clip: true

    Rectangle {
        color: Material.background
        width: parent.width
        height: Math.max(parent.contentHeight, parent.height)
        z: -100
    }

    // Use FollowCurve for smoother scrolling on touchpads
    boundsBehavior: Flickable.FollowCurve | Flickable.StopAtBounds
}

