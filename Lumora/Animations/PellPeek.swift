import SwiftUI

extension View {
    /// Lets Pell peek in over this screen with whatever it has to say
    /// (`AppModel.pell`). Pell comes in at mid-height, over the sky and
    /// clear of the bars and buttons people reach for at the bottom.
    func pellPeekHost(_ scope: PellTip.Scope) -> some View {
        modifier(PellPeekHost(scope: scope))
    }
}

private struct PellPeekHost: ViewModifier {
    var scope: PellTip.Scope

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @State private var askingName = false
    @State private var name = ""

    func body(content: Content) -> some View {
        let tip = app.pell.current.flatMap { $0.scope == scope ? $0 : nil }
        content
            // Mid-height over the sky on the tabs; higher on the focus setup,
            // over the star preview, so the duration and intention stay clear.
            .overlay(alignment: scope == .focus ? .top : .center) {
                if let tip {
                    PellPeekView(tip: tip) { action in
                        if action == .askName {
                            name = app.preferences.displayName
                            askingName = true
                        }
                        app.pell.dismiss()
                    }
                    .padding(.top, scope == .focus ? 150 : 0)
                    .transition(motion == .reduced ? .opacity
                                : .move(edge: tip.edge == .trailing ? .trailing : .leading).combined(with: .opacity))
                    .id(tip.id)
                }
            }
            .animation(motion == .reduced ? .easeInOut(duration: 0.25) : LMSpring.bloom, value: tip?.id)
            .alert(String(localized: "What should I call you?"), isPresented: $askingName) {
                TextField(String(localized: "Your name"), text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                Button(String(localized: "Not now"), role: .cancel) {}
                Button(String(localized: "Save")) { saveName() }
            } message: {
                Text("Just a first name is plenty. It stays on your device.")
            }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        app.preferences.displayName = String(trimmed.prefix(40))
        app.savePreferences()
        app.pell.offer(PellTip(id: "pell.nameThanks",
                               message: String(localized: "Nice to meet you, \(trimmed)! Tap any light in your sky to see the session that made it."),
                               mood: .happy, edge: .leading), after: .seconds(0.6))
    }
}

/// Pell, half behind the edge of the screen, with a speech bubble. Slides in,
/// tips its head, and leaves by itself after a while (unless it asked
/// something, or VoiceOver is reading). Tap the bubble or swipe Pell away to
/// dismiss sooner.
private struct PellPeekView: View {
    var tip: PellTip
    var onDone: (PellTip.Action?) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.motionLevel) private var motion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var tilted = false
    @GestureState private var drag: CGFloat = 0

    private static let pellSize: CGFloat = 104

    var body: some View {
        let trailing = tip.edge == .trailing
        HStack(alignment: .bottom, spacing: 0) {
            if trailing {
                Spacer(minLength: LMSpace.l)
                bubble
                pell(trailing: true)
            } else {
                pell(trailing: false)
                bubble
                Spacer(minLength: LMSpace.l)
            }
        }
        .offset(x: drag)
        .gesture(DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                // Only toward Pell's own edge, the way it came in.
                let x = value.translation.width
                state = trailing ? max(0, x) : min(0, x)
            }
            .onEnded { value in
                if abs(value.translation.width) > 60 { onDone(nil) }
            })
        .accessibilityElement(children: .contain)
        .task(id: tip.id) {
            app.haptics.selection()
            AccessibilityNotification.Announcement(String(localized: "Pell: \(tip.message)")).post()
            if motion != .reduced {
                try? await Task.sleep(for: .seconds(0.25))
                withAnimation(LMSpring.bloom) { tilted = true }
            }
            // A question waits for an answer; with VoiceOver, nothing leaves on a timer.
            guard !voiceOver, tip.action == nil else { return }
            try? await Task.sleep(for: .seconds(6.5))
            onDone(nil)
        }
    }

    private func pell(trailing: Bool) -> some View {
        PellFace(expression: tip.mood, fill: 0.34)
            .frame(width: Self.pellSize, height: Self.pellSize)
            // Half hidden behind the edge, head tipped toward the bubble.
            .rotationEffect(.degrees(tilted ? (trailing ? -14 : 14) : (trailing ? 18 : -18)))
            .offset(x: trailing ? Self.pellSize * 0.18 : -Self.pellSize * 0.18, y: 6)
            .accessibilityHidden(true)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: LMSpace.xs) {
            Text(tip.message)
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text("Pell: \(tip.message)"))
                .accessibilityAction(named: Text("Dismiss")) { onDone(nil) }
            if let action = tip.action, let title = tip.actionTitle {
                Button {
                    onDone(action)
                } label: {
                    Text(title)
                        .font(LMFont.callout.weight(.semibold))
                        .foregroundStyle(LMColor.reward)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pell.action")
            }
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .frame(maxWidth: 300, alignment: .leading)
        .glassCard(radius: 22, border: LMColor.reward.opacity(0.35))
        .padding(.bottom, Self.pellSize * 0.35)
        .contentShape(Rectangle())
        .onTapGesture { onDone(nil) }
        .accessibilityIdentifier("pell.tip")
    }
}
