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
    // Dimensions (8pt grid system)
    // ============================================
    readonly property int borderRadius: 8
    readonly property int borderWidth: 2

    // Spacing
    readonly property int spacingXxs: 2
    readonly property int spacingXs: 4
    readonly property int spacingSm: 8
    readonly property int spacingMd: 16
    readonly property int spacingLg: 24
    readonly property int spacingXl: 32

    // Margins
    readonly property int marginSm: 8
    readonly property int marginMd: 16
    readonly property int marginLg: 24

    // Card dimensions (8pt grid)
    readonly property int pcCardWidth: 304
    readonly property int pcCardHeight: 320
    readonly property int appCardWidth: 224
    readonly property int appCardHeight: 288
    readonly property int appIconWidth: 192
    readonly property int appIconHeight: 256

    // ============================================
    // Animation Durations (ms)
    // ============================================
    readonly property int animationDurationFast: 80
    readonly property int animationDurationNormal: 200

    // ============================================
    // Font Sizes (points) - Hierarchical system
    // ============================================
    // Display: Large headings
    readonly property int fontDisplay: 32
    // Title: Card titles, page headers
    readonly property int fontTitle: 24
    // Subtitle: Secondary headings
    readonly property int fontSubtitle: 20
    // Body: Primary content text
    readonly property int fontBody: 16
    // Caption: Small text, labels
    readonly property int fontCaption: 14
    // Small: Tertiary text
    readonly property int fontSmall: 12
}
