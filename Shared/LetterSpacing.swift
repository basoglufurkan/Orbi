import SwiftUI

/// Letter spacing that respects the script: connected scripts (Arabic) must
/// never be tracked apart, so tracking collapses to 0 there.
enum LMTracking {
    static let allowsLetterSpacing: Bool = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        return !["ar", "fa", "ur", "he"].contains { language.hasPrefix($0) }
    }()
}

extension Text {
    func lmTracking(_ value: CGFloat) -> Text {
        tracking(LMTracking.allowsLetterSpacing ? value : 0)
    }
}

extension View {
    func lmTracking(_ value: CGFloat) -> some View {
        tracking(LMTracking.allowsLetterSpacing ? value : 0)
    }
}
