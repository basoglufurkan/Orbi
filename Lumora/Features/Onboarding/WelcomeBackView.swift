import SwiftUI

/// Shown once when iCloud brings back a universe while onboarding is still
/// on screen (a reinstall, a new device): instead of the app jumping to Home
/// on its own, Pell says the sky came home and the user steps in.
struct WelcomeBackView: View {
    var onContinue: () -> Void

    @Environment(\.motionLevel) private var motion
    @State private var appeared = false

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .home, light: 0.6, starOpacity: 1)
            VStack(spacing: LMSpace.l) {
                // Scrolls at large text sizes; the button always stays on screen.
                FittingScrollView(alignment: .center) {
                    VStack(spacing: LMSpace.l) {
                        PellView(mood: .happy, greetUntil: .now.addingTimeInterval(2.4), showsLabel: false)
                            .scaleEffect(1.6)
                            .frame(height: 180)
                            .scaleEffect(appeared || motion == .reduced ? 1 : 0.7)
                        VStack(spacing: LMSpace.s) {
                            Text("Your sky came back.")
                                .font(LMFont.voice(.largeTitle))
                                .foregroundStyle(LMColor.textPrimary)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                            Text("I found your universe in iCloud. Every star is right where you left it.")
                                .font(LMFont.body)
                                .foregroundStyle(LMColor.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: appeared || motion == .reduced ? 0 : 16)
                    }
                    .padding(.vertical, LMSpace.l)
                }
                CosmicButton(title: "Let's go", systemImage: "sparkle", kind: .reward) { onContinue() }
                    .accessibilityIdentifier("welcomeBack.continue")
            }
            .opacity(appeared ? 1 : 0)
            .padding(.horizontal, LMSpace.l)
            .readableColumn()
            .padding(.bottom, LMSpace.m)
        }
        .onAppear {
            withAnimation(LMSpring.settle.delay(0.15)) { appeared = true }
        }
    }
}
