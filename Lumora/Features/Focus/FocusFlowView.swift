import SwiftUI

/// Full-screen container for everything between "Begin Focus" and returning
/// home: setup → active focus → completion → break.
struct FocusFlowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let state = app.timer.state
        ZStack {
            LMColor.bgBase.ignoresSafeArea()
            content(state)
        }
        .pellPeekHost(.focus)
        .animation(LMCurve.emerge.animation(duration: 0.6), value: stage(state))
        // Notes about setup don't follow into the session.
        .onChange(of: stage(state)) { _, _ in app.pell.clear(scope: .focus) }
    }

    private enum Stage: Hashable { case setup, focus, celebrate, rest, restComplete, recordError, none }

    private func stage(_ state: TimerState) -> Stage {
        if state.pendingResult != nil { return app.timer.pendingReward == nil ? .recordError : .celebrate }
        switch state.phase {
        case .preparing: return .setup
        case .focusing, .paused: return .focus
        case .onBreak: return .rest
        case .idle: return app.showBreakComplete ? .restComplete : .none
        case .completed, .interrupted: return .none
        }
    }

    @ViewBuilder
    private func content(_ state: TimerState) -> some View {
        switch stage(state) {
        case .setup:
            FocusSetupView().transition(.opacity)
        case .focus:
            ActiveFocusView().transition(.opacity)
        case .celebrate:
            if let reward = app.timer.pendingReward {
                CelebrationSequenceView(reward: reward, autoBreak: state.phase == .onBreak)
                    .id(reward.sessionID)
                    .transition(.opacity)
            }
        case .rest:
            BreakView().transition(.opacity)
        case .restComplete:
            BreakCompleteView().transition(.opacity)
        case .recordError:
            RecordErrorView().transition(.opacity)
        case .none:
            Color.clear.onAppear { app.timer.acknowledge() }
        }
    }
}

/// Shown only if the reward transaction failed; the timer result is kept in
/// the checkpoint, so retrying can never lose or duplicate the session.
private struct RecordErrorView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: LMSpace.l) {
            Spacer()
            Text("Your light is safe.")
                .font(LMFont.voice(.largeTitle))
                .foregroundStyle(LMColor.textPrimary)
            Text("We couldn't place your star just yet. Your session is kept and will be added when you try again.")
                .font(LMFont.body)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            if let error = app.timer.lastError {
                Text(error).font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
            }
            Spacer()
            CosmicButton(title: "Try again") { app.timer.retryPendingRecord() }
            // A way out if saving keeps failing: the session stays kept and is
            // retried the next time Lumora comes forward.
            Button(String(localized: "Later")) { app.recordErrorDeferred = true }
                .font(LMFont.headline.weight(.medium))
                .foregroundStyle(LMColor.textSecondary)
                .frame(minHeight: 44)
        }
        .padding(LMSpace.l)
    }
}
