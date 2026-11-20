import SwiftUI
import UIKit

/// Semantic color tokens (Foundations · Semantic tokens).
///
/// Night (dark) is the signature appearance; Dawn (light) mirrors it. Every
/// token resolves dynamically, so a single view hierarchy serves both, and
/// Increase Contrast lifts hairlines and tertiary text as specified.
enum LMColor {
    static let bgBase = dynamic(light: 0xF5F4FF, dark: Palette.deepSpace)
    static let bgRaised = dynamic(light: 0xFFFFFF, dark: Palette.midnightIndigo)

    static let textPrimary = dynamic(light: 0x151936, dark: Palette.softWhite)
    static let textSecondary = dynamic(light: 0x454A78, dark: 0xB9BCE3)
    static let textTertiary = Color(uiColor: UIColor { t in
        let highContrast = t.accessibilityContrast == .high
        if t.userInterfaceStyle == .dark {
            return UIColor(hex: highContrast ? 0xB9BCE3 : 0x8C90C2)
        }
        return UIColor(hex: highContrast ? 0x454A78 : 0x5E6290)
    })

    static let focus = dynamic(light: 0x5B4BE0, dark: Palette.cosmicViolet)
    static let reward = dynamic(light: 0x9A6200, dark: Palette.warmGold)
    static let rewardFill = Color(hex: Palette.warmGold)
    static let calm = dynamic(light: 0x0F7A90, dark: Palette.starlightCyan)
    static let warm = dynamic(light: 0xC23E74, dark: Palette.nebulaPink)

    /// Labels on violet, cyan, gold or pink fills are always Deep Space.
    static let onAccent = Color(hex: Palette.deepSpace)

    static let hairline = Color(uiColor: UIColor { t in
        let alpha: CGFloat = t.accessibilityContrast == .high ? 0.24 : 0.10
        return t.userInterfaceStyle == .dark
            ? UIColor(hex: Palette.softWhite, alpha: alpha)
            : UIColor(hex: Palette.midnightIndigo, alpha: alpha)
    })

    static let glassTint = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: Palette.softWhite, alpha: 0.06)
            : UIColor(hex: 0xFFFFFF, alpha: 0.72)
    })

    /// Solid replacement for glass when Reduce Transparency is on.
    static let glassSolid = dynamic(light: 0xFFFFFF, dark: Palette.midnightIndigo)

    /// Primary "starlight" button fill: soft white at night, deep space at dawn.
    static let starlightFill = dynamic(light: Palette.midnightIndigo, dark: Palette.softWhite)
    static let starlightLabel = dynamic(light: Palette.softWhite, dark: Palette.deepSpace)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
