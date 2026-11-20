import SwiftUI

/// Screens without a navigation bar let content scroll up under the status
/// bar and Dynamic Island. This veil fades that content into the sky so text
/// never collides with the clock. It covers only the top safe area, so a
/// screen at rest looks exactly the same.
struct StatusBarScrim: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { geo in
                // Pinned to the top of the screen wherever this view starts;
                // overlays aren't clipped, so it can reach above its host.
                LinearGradient(stops: [.init(color: LMColor.bgBase.opacity(0.98), location: 0),
                                       .init(color: LMColor.bgBase.opacity(0.92), location: 0.78),
                                       .init(color: LMColor.bgBase.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: geo.size.width, height: geo.safeAreaInsets.top)
                    .offset(y: -geo.frame(in: .global).minY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Fades scrolled content out under the status bar; see `StatusBarScrim`.
    func statusBarScrim() -> some View { modifier(StatusBarScrim()) }
}
