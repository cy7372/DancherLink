pragma Singleton
import QtQuick 2.15
import QtQuick.Controls.Material 2.15

QtObject {
    // ============================================
    // Background Colors
    // ============================================
    readonly property color backgroundPrimary: "#303030"
    readonly property color backgroundHover: "#404040"
    readonly property color backgroundHighlighted: "#505050"
    readonly property color backgroundPopup: "#424242"

    // ============================================
    // Accent Colors
    // ============================================
    readonly property color accentPrimary: "#87CEEB"  // SkyBlue
    readonly property color accentError: "#FF6B6B"

    // ============================================
    // Text Colors
    // ============================================
    readonly property color textPrimary: Material.foreground
    readonly property color textSecondary: Material.hintTextColor
    readonly property color groupTitle: "#87CEEB"

    // ============================================
    // Dimensions
    // ============================================
    readonly property int borderRadius: 8
    readonly property int borderWidth: 2

    // ============================================
    // Animation Durations (ms)
    // ============================================
    readonly property int animationDurationFast: 100
    readonly property int animationDurationNormal: 200

    // ============================================
    // Font Sizes (points)
    // ============================================
    readonly property int fontTitle: 20
    readonly property int fontSubtitle: 16
    readonly property int fontBody: 14
    readonly property int fontCaption: 12
}
