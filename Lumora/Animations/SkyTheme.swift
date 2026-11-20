import SwiftUI

/// The colours of the nebula washes behind Today, the Universe and the other
/// home screens. Classic is everyone's; the rest come with Orbi+.
enum SkyTheme: String, CaseIterable, Identifiable, Sendable {
    case classic, aurora, ember, ocean, eclipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .aurora: String(localized: "Aurora")
        case .ember: String(localized: "Ember")
        case .ocean: String(localized: "Ocean")
        case .eclipse: String(localized: "Eclipse")
        }
    }

    var isPlus: Bool { self != .classic }

    /// The main wash and the side glow (sRGB hex).
    var washes: (primary: UInt32, secondary: UInt32) {
        switch self {
        case .classic: (Palette.cosmicViolet, Palette.nebulaPink)
        case .aurora: (0x2FD6B5, 0x8B7CFF)
        case .ember: (0xFF8A3D, 0xFF5E7E)
        case .ocean: (0x2F7BFF, 0x70E1F5)
        case .eclipse: (0xFFD58A, 0x5B4BE0)
        }
    }

    /// The chosen theme, or Classic while Orbi+ isn't active.
    static func current(raw: String, plusActive: Bool) -> SkyTheme {
        plusActive ? SkyTheme(rawValue: raw) ?? .classic : .classic
    }
}
