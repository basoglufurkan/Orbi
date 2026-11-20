import SwiftUI

/// What a focus session was for. Encoded by hue *and* star shape, so color
/// is never the only signal (Foundations · Celestial object library).
enum FocusCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case study, work, coding, reading, creative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .study: String(localized: "Study")
        case .work: String(localized: "Work")
        case .coding: String(localized: "Coding")
        case .reading: String(localized: "Reading")
        case .creative: String(localized: "Creative")
        }
    }

    var hex: UInt32 {
        switch self {
        case .study: Palette.warmGold
        case .work: Palette.cosmicViolet
        case .coding: Palette.starlightCyan
        case .reading: Palette.softWhite
        case .creative: Palette.nebulaPink
        }
    }

    /// The category's colour. Reading's soft white turns to a muted slate at
    /// Dawn (light), where white would vanish on pale cards, chips and
    /// widgets; the sky painters ink their Dawn stars on top of it.
    var color: Color {
        guard self == .reading else { return Color(hex: hex) }
        return Color(uiColor: UIColor { traits in
            let value: UInt32 = traits.userInterfaceStyle == .dark ? hex : 0x7A80B4
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        })
    }

    /// The category name for use mid-sentence ("Small coding star").
    /// Lowercased with locale rules, except in German, where nouns stay capitalized.
    var inlineName: String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return language.hasPrefix("de") ? displayName : displayName.localizedLowercase
    }

    /// Number of star points; 0 means a round star.
    var starPoints: Int {
        switch self {
        case .work: 4
        case .study: 5
        case .coding: 6
        case .creative: 8
        case .reading: 0
        }
    }

    init(storedValue: String) {
        self = FocusCategory(rawValue: storedValue) ?? .work
    }
}
