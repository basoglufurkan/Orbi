import SwiftUI

/// Raw brand colors from the Lumora design system (Foundations, p.2).
/// Semantic, appearance-aware tokens live in `LMColor` inside the app target.
enum Palette {
    static let deepSpace: UInt32 = 0x090B1F
    static let midnightIndigo: UInt32 = 0x151936
    static let cosmicViolet: UInt32 = 0x8B7CFF
    static let nebulaPink: UInt32 = 0xFF8FB8
    static let starlightCyan: UInt32 = 0x70E1F5
    static let warmGold: UInt32 = 0xFFD58A
    static let softWhite: UInt32 = 0xF7F7FF
    static let dawnBase: UInt32 = 0xF5F4FF
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
