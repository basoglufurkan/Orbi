import SwiftUI

/// "Something has surfaced": tap to flip the artifact card (3D Y-rotation,
/// 1.1 s Bloom; crossfade with Reduce Motion).
struct ArtifactRevealView: View {
    let definition: AchievementDefinition
    let unlockedAt: Date

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @Environment(\.dismiss) private var dismiss
    @State private var flipped = false

    var body: some View {
        ZStack {
            CosmicBackgroundView(mood: .reward, light: 0.5)
            VStack(spacing: LMSpace.l) {
                VStack(spacing: LMSpace.xs) {
                    EyebrowText("\(definition.rarity == .common ? String(localized: "Artifact") : String(localized: "Rare artifact")) · \(String(localized: "No. \(String(format: "%03d", definition.number))"))",
                                color: LMColor.reward)
                    Text(flipped ? definition.title : String(localized: "Something has surfaced."))
                        .font(LMFont.voice(.title))
                        .foregroundStyle(LMColor.textPrimary)
                        .contentTransition(.opacity)
                }
                .padding(.top, LMSpace.xl)

                card
                    .onTapGesture { reveal() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(flipped ? Text("\(definition.title). \(definition.lore)") : Text("Tap to reveal artifact"))

                Spacer()
                if flipped {
                    Text(placementLine)
                        .font(LMFont.callout.weight(.regular))
                        .foregroundStyle(LMColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                CosmicButton(title: flipped ? "Add to Collection" : "Reveal", kind: .reward) {
                    if flipped { dismiss() } else { reveal() }
                }
                ShareCardLink(content: shareCard,
                              caption: String(localized: "I found “\(definition.title)” in my Orbi universe. ✦")) {
                    Text("Share card")
                }
                .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 52))
            }
            .padding(LMSpace.l)
        }
        .presentationBackground(LMColor.bgBase)
    }

    private var placementLine: String {
        String(localized: "Earned \(unlockedAt.formatted(date: .long, time: .omitted)). It now lives in your collection forever.")
    }

    private var shareCard: ShareCardContent {
        ShareCardContent(subject: .artifact(definition.motif),
                         eyebrow: "\(definition.rarity == .common ? String(localized: "Artifact") : String(localized: "Rare artifact")) · \(String(localized: "No. \(String(format: "%03d", definition.number))"))",
                         title: definition.title,
                         stat: String(localized: "Found \(unlockedAt.formatted(date: .long, time: .omitted))"))
    }

    private func reveal() {
        guard !flipped else { return }
        app.haptics.success()
        if motion == .reduced {
            withAnimation(.easeInOut(duration: 0.4)) { flipped = true }
        } else {
            withAnimation(LMSpring.bloom.speed(0.5)) { flipped = true }
        }
    }

    private var card: some View {
        ZStack {
            back.opacity(flipped ? 0 : 1)
            front.opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(motion == .reduced ? 0 : 180), axis: (0, 1, 0))
        }
        .frame(width: 270, height: 360)
        .rotation3DEffect(.degrees(flipped && motion != .reduced ? 180 : 0), axis: (0, 1, 0), perspective: 0.6)
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x2A2363), Color(hex: Palette.midnightIndigo)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(LMColor.rewardFill.opacity(0.4), lineWidth: 1))
            .overlay {
                VStack(spacing: LMSpace.m) {
                    Image(systemName: "diamond").font(.system(size: 44, weight: .light)).foregroundStyle(LMColor.rewardFill)
                    Text("TAP TO REVEAL").font(LMFont.eyebrow).lmTracking(1.6).foregroundStyle(LMColor.rewardFill)
                }
            }
            .shadow(color: LMColor.rewardFill.opacity(0.25), radius: 30)
    }

    private var front: some View {
        VStack(spacing: LMSpace.s) {
            HStack {
                Text("No. \(String(format: "%03d", definition.number))").font(LMFont.footnote)
                Spacer()
                Text(definition.rarity.label.localizedUppercase).font(LMFont.eyebrow).lmTracking(1.2)
            }
            .foregroundStyle(LMColor.reward)
            ArtifactMotifView(motif: definition.motif, earned: true).frame(height: 130)
            Text(definition.title).font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            Text(definition.lore)
                .font(LMFont.footnote.weight(.regular))
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            Text(unlockedAt.formatted(date: .abbreviated, time: .omitted))
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textTertiary)
        }
        .padding(LMSpace.l)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(hex: Palette.midnightIndigo)))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(LMColor.rewardFill.opacity(0.5), lineWidth: 1))
        .shadow(color: LMColor.rewardFill.opacity(0.3), radius: 30)
    }
}
