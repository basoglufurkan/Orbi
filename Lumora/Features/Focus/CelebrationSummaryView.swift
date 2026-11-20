import SwiftUI
import UserNotifications

/// Stage 10 · Summary rises: headline, line, cards and actions rise 18pt
/// with the Settle spring, staggered 80 ms. Numbers count up; the goal bar
/// fills from where today was to where it is now.
struct CelebrationSummaryView: View {
    let reward: SessionReward
    let plan: CelebrationPlan
    var autoBreak = false

    @Environment(AppModel.self) private var app
    @State private var shown = false
    @State private var counted = false
    @State private var artifact: AchievementDefinition?
    @State private var askNotifications = false
    @State private var taskMarkedDone = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.motionLevel) private var motion

    var body: some View {
        GeometryReader { geo in
            // Scrolls only when needed (small iPhones, large Dynamic Type);
            // the top third stays clear for the constellation. Measured on the
            // full height so the pinned actions below don't pull text into the sky.
            let topGap = (geo.size.height + geo.safeAreaInsets.bottom) * 0.3
            ScrollView {
                Group {
                    if plan.kind == .milestone, let planet = reward.planetBorn {
                        milestone(planet: planet, topGap: topGap)
                    } else {
                        standard(topGap: topGap)
                    }
                }
                .padding(.horizontal, LMSpace.l)
                .readableColumn()
                .padding(.bottom, LMSpace.s)
                .frame(minHeight: geo.size.height, alignment: .bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .statusBarScrim()
        }
        // The next step stays in reach however many cards this session earned.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isMilestone {
                rise(7) { actions }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                    .padding(.top, LMSpace.l)
                    .padding(.bottom, LMSpace.xs)
                    .background(
                        LinearGradient(stops: [.init(color: LMColor.bgBase.opacity(0), location: 0),
                                               .init(color: LMColor.bgBase, location: 0.3),
                                               .init(color: LMColor.bgBase, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    )
            }
        }
        .onAppear {
            shown = true
            withAnimation(.easeOut(duration: 1.0).delay(0.25)) { counted = true }
            Task { await checkNotificationPrompt() }
        }
        .sheet(item: $artifact) { def in
            ArtifactRevealView(definition: def, unlockedAt: reward.endedAt)
        }
        .telemetryScreen("celebration")
    }

    private var pellMood: PellExpression {
        if reward.outcome == .tooShort { return .calm }
        return reward.todayMinutesBefore < reward.goalMinutes && reward.todayMinutes >= reward.goalMinutes ? .happy : .proud
    }

    // MARK: Standard

    private func standard(topGap: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            Spacer(minLength: topGap)
            rise(0) {
                HStack(alignment: .center, spacing: LMSpace.s) {
                    Text(reward.outcome == .tooShort ? String(localized: "A few quiet minutes.")
                         : app.preferences.displayName.isEmpty ? String(localized: "You did it.")
                         : String(localized: "You did it, \(app.preferences.displayName)."))
                        .font(LMFont.voice(.largeTitle))
                        .foregroundStyle(Color(hex: 0xFFF1D6).blendedForScheme(LMColor.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("celebration.headline")
                    Spacer(minLength: 0)
                    // Pell cheers you on: proud for a star, delighted when the day's goal is met.
                    PellFace(expression: pellMood, fill: 0.34)
                        .frame(width: 76, height: 76)
                        .padding(-12)
                }
            }
            rise(1) {
                Text(line)
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if reward.outcome != .tooShort {
                rise(2) {
                    AdaptiveStack(spacing: LMSpace.s) {
                        StatisticsCardView(title: String(localized: "Focus earned"),
                                           value: "+" + String(localized: "\(counted ? reward.focusedMinutes : 0) min"))
                            .contentTransition(.numericText())
                        StatisticsCardView(title: String(localized: "Today"),
                                           value: LMFormat.minutes(counted ? reward.todayMinutes : reward.todayMinutesBefore))
                            .contentTransition(.numericText())
                    }
                }
                rise(3) {
                    AdaptiveStack(spacing: LMSpace.s) {
                        newStarCard
                        goalCard
                    }
                }
                rise(4) { constellationBanner }
                rise(4) { TogetherSummaryCard(sessionID: reward.sessionID) }
                rise(4) { OdysseySummaryCard(sessionID: reward.sessionID) }
                rise(4) { HabitSummaryCard(sessionID: reward.sessionID) }
                if let task = reward.task {
                    rise(5) { taskCard(task) }
                }
                ForEach(Array(reward.newAchievements.prefix(2).enumerated()), id: \.element.id) { i, def in
                    rise(5 + i) { artifactCard(def) }
                }
            }
            if askNotifications {
                rise(6) { notificationCard }
            }
        }
    }

    private var isMilestone: Bool { plan.kind == .milestone && reward.planetBorn != nil }

    private var line: String {
        switch reward.outcome {
        case .completed: String(localized: "\(reward.focusedMinutes) minutes of focus. A new star in your universe.")
        case .endedEarly: String(localized: "\(reward.focusedMinutes) minutes of focus. Still yours.")
        case .tooShort: String(localized: "Sessions under \(app.rules.minimumQualifyingSeconds / 60) minutes rest without a star. Nothing changed, nothing was lost.")
        }
    }

    private var newStarCard: some View {
        HStack(spacing: LMSpace.s) {
            CategoryGlyph(category: reward.category, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                EyebrowText(String(localized: "New"), color: reward.category.color)
                Text(reward.outcome == .endedEarly
                     ? String(localized: "Small \(reward.category.inlineName) star")
                     : String(localized: "\(reward.category.displayName) star"))
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: typeSize.isAccessibilitySize)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, typeSize.isAccessibilitySize ? LMSpace.s : 0)
        .frame(maxWidth: .infinity, minHeight: 86)
        .glassCard(radius: 22, tint: reward.category.color, border: reward.category.color.opacity(0.35))
        .accessibilityElement(children: .combine)
    }

    private var goalCard: some View {
        let progress = counted ? reward.goalProgress : reward.goalProgressBefore
        return VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack(spacing: 2) {
                EyebrowText(String(localized: "Daily goal"))
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("\(Int((progress * 100).rounded()))%")
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LMColor.textPrimary.opacity(0.1))
                    Capsule().fill(LMColor.focus).frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 6)
            Text("\(reward.todayMinutes) of \(reward.goalMinutes) min")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textSecondary)
        }
        .padding(LMSpace.m)
        .frame(maxWidth: .infinity, minHeight: 86)
        .glassCard(radius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Daily goal \(Int((reward.goalProgress * 100).rounded())) percent, \(reward.todayMinutes) of \(reward.goalMinutes) minutes"))
    }

    private var constellationBanner: some View {
        let text: AttributedString = {
            if reward.constellationFormed != nil {
                return AttributedString(String(localized: "Today's constellation is complete."))
            }
            let n = reward.starsUntilConstellation
            var lead = AttributedString(n == 1 ? String(localized: "One more session") : String(localized: "\(n) more sessions"))
            lead.font = LMFont.callout.weight(.bold)
            let tail = n == 1 ? String(localized: " completes today's constellation.") : String(localized: " complete today's constellation.")
            return lead + AttributedString(tail)
        }()
        return HStack(spacing: LMSpace.s) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(LMColor.reward)
                .accessibilityHidden(true)
            Text(text)
                .font(LMFont.callout.weight(.regular))
                .foregroundStyle(LMColor.reward)
            Spacer(minLength: 0)
        }
        .padding(LMSpace.m)
        .glassCard(radius: 22, tint: LMColor.rewardFill, border: LMColor.rewardFill.opacity(0.3))
    }

    /// "2 of 4 sessions for Essay draft", with a gentle offer to close the
    /// task once the estimate is reached. Never shown for too-short sessions.
    private func taskCard(_ task: TaskSnapshot) -> some View {
        let done = task.isCompleted || taskMarkedDone
        let tint = task.category.color
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            HStack(alignment: .top, spacing: LMSpace.s) {
                CategoryGlyph(category: task.category, size: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    EyebrowText(done ? String(localized: "Task done") : String(localized: "Task"), color: tint)
                    Text(taskLine(task))
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    TaskProgressDots(progress: task.progress, tint: tint, size: 8)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(done ? String(localized: "Task done. \(taskLine(task))") : taskLine(task)))
            .accessibilityIdentifier("celebration.task")

            if task.progress.reachedEstimate, !done {
                VStack(alignment: .leading, spacing: LMSpace.xs) {
                    Text("That's every session you planned.")
                        .font(LMFont.callout.weight(.regular))
                        .foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        app.haptics.selection()
                        app.tasks.setCompleted(taskID: task.id, true)
                        withAnimation(LMSpring.settle) { taskMarkedDone = true }
                    } label: {
                        Label(String(localized: "Mark task done?"), systemImage: "checkmark")
                            .font(LMFont.callout.weight(.semibold))
                            .foregroundStyle(LMColor.calm)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, typeSize.isAccessibilitySize ? LMSpace.xs : 0)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(LMColor.calm.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(LMColor.calm.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(Text("Mark \(task.title) done"))
                    .accessibilityIdentifier("celebration.markTaskDone")
                }
                .transition(.opacity)
            }
        }
        .padding(LMSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22, tint: tint, border: tint.opacity(0.35))
    }

    /// Another session continues the same task unless it's done.
    private var continuingTaskID: UUID? {
        guard let task = reward.task, !task.isCompleted, !taskMarkedDone else { return nil }
        return task.id
    }

    private func taskLine(_ task: TaskSnapshot) -> String {
        let p = task.progress
        if p.hasEstimate {
            return p.estimate == 1
                ? String(localized: "\(p.sessionsDone) of 1 session for \(task.title)")
                : String(localized: "\(p.sessionsDone) of \(p.estimate) sessions for \(task.title)")
        }
        return p.sessionsDone == 1
            ? String(localized: "1 session for \(task.title)")
            : String(localized: "\(p.sessionsDone) sessions for \(task.title)")
    }

    private func artifactCard(_ def: AchievementDefinition) -> some View {
        Button {
            artifact = def
        } label: {
            HStack(spacing: LMSpace.s) {
                Image(systemName: "diamond.fill").foregroundStyle(LMColor.reward)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(def.rarity == .common ? String(localized: "New artifact") : String(localized: "New · \(def.rarity.label)"),
                                color: LMColor.reward)
                    Text(def.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Text("Reveal").font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
                }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(LMColor.textTertiary)
            }
            .padding(LMSpace.m)
            .glassCard(radius: 22)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint(Text("Reveals the artifact"))
        .accessibilityIdentifier("celebration.artifact")
    }

    private var notificationCard: some View {
        AdaptiveStack(spacing: LMSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: LMSpace.s) {
                Image(systemName: "bell").foregroundStyle(LMColor.calm)
                Text("Want a soft chime when a star is born?")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: LMSpace.s) {
                Button(String(localized: "Allow")) {
                    Task {
                        await app.notifications.requestAuthorization(source: "celebration")
                        app.preferences.hasSeenNotificationPrompt = true
                        app.dataStore.save()
                        withAnimation(LMSpring.settle) { askNotifications = false }
                    }
                }
                .font(LMFont.callout.weight(.semibold))
                .foregroundStyle(LMColor.calm)
                .frame(minWidth: 44, minHeight: 44)
                Button {
                    app.preferences.hasSeenNotificationPrompt = true
                    app.dataStore.save()
                    withAnimation(LMSpring.settle) { askNotifications = false }
                } label: {
                    Image(systemName: "xmark").font(.footnote).foregroundStyle(LMColor.textTertiary).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Not now"))
                .accessibilityIdentifier("celebration.notNow")
            }
        }
        .padding(.horizontal, LMSpace.m)
        .padding(.vertical, LMSpace.s)
        .glassCard(radius: 22)
    }

    private var actions: some View {
        VStack(spacing: LMSpace.s) {
            CosmicButton(title: "Explore My Universe") {
                let starID = reward.star?.id
                app.timer.acknowledge()
                app.showInUniverse(starID)
            }
            .accessibilityIdentifier("celebration.explore")
            AdaptiveStack(horizontalAlignment: .center, spacing: LMSpace.s) {
                if autoBreak {
                    CosmicButton(title: "Continue to your break", kind: .secondary, height: 52) {
                        app.timer.acknowledge()
                    }
                } else {
                    CosmicButton(title: "Take a \(app.preferences.shortBreakMinutes)-min break", kind: .secondary, height: 52) {
                        app.timer.startBreak()
                    }
                    .accessibilityIdentifier("celebration.break")
                }
                RoundControlButton(systemImage: "arrow.counterclockwise", label: "Start another session", size: 52) {
                    app.beginFocus(taskID: continuingTaskID)
                }
            }
        }
    }

    // MARK: Milestone

    private func milestone(planet: CelestialSnapshot, topGap: CGFloat) -> some View {
        VStack(spacing: LMSpace.s) {
            rise(0) {
                Text("\(String(localized: "Milestone")) · \(String(localized: "Session")) \(reward.totalQualifyingSessions)".uppercased())
                    .font(LMFont.eyebrow).lmTracking(1.6)
                    .foregroundStyle(LMColor.reward)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 34)
                    .overlay(Capsule().strokeBorder(LMColor.rewardFill.opacity(0.5), lineWidth: 1))
            }
            .padding(.top, LMSpace.m)
            Spacer(minLength: topGap)
            rise(1) {
                Text("\(planet.name) is born.")
                    .font(LMFont.voice(.largeTitle))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color(hex: 0xFFF1D6).blendedForScheme(LMColor.textPrimary))
                    .accessibilityAddTraits(.isHeader)
            }
            rise(2) {
                Text(milestoneLine(planet))
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            rise(3) {
                AdaptiveStack(spacing: LMSpace.s) {
                    StatisticsCardView(title: String(localized: "Unlocked"), value: unlockedTitle)
                    if let def = reward.newAchievements.first {
                        Button { artifact = def } label: {
                            StatisticsCardView(title: String(localized: "Artifact"), value: def.title, highlight: LMColor.reward)
                        }
                        .buttonStyle(PressScaleStyle())
                    } else {
                        StatisticsCardView(title: String(localized: "Focus earned"), value: "+" + String(localized: "\(reward.focusedMinutes) min"))
                    }
                }
            }
            if let task = reward.task {
                rise(3) { taskCard(task) }
            }
            rise(4) {
                VStack(spacing: LMSpace.s) {
                    CosmicButton(title: "Visit \(planet.name)", kind: .reward) {
                        app.timer.acknowledge()
                        app.showInUniverse(planet.id)
                    }
                    AdaptiveStack(horizontalAlignment: .center, spacing: LMSpace.s) {
                        ShareCardLink(content: shareCard(planet),
                                      caption: String(localized: "\(planet.name) was born in my Orbi universe after \(reward.totalQualifyingSessions) focus sessions. ✦")) {
                            Text("Share this moment")
                        }
                        .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 52))
                        RoundControlButton(systemImage: "arrow.counterclockwise", label: "Start another session", size: 52) {
                            app.beginFocus(taskID: continuingTaskID)
                        }
                    }
                }
            }
        }
    }

    private func shareCard(_ planet: CelestialSnapshot) -> ShareCardContent {
        ShareCardContent(subject: .celestial(planet),
                         eyebrow: "\(String(localized: "Milestone")) · \(String(localized: "World \(planet.ordinal)"))",
                         title: String(localized: "\(planet.name) is born."),
                         stat: String(localized: "\(reward.totalQualifyingSessions) focus sessions of light"))
    }

    private var unlockedTitle: String {
        let opened = UniverseRegion.allCases.first { $0.unlockSessions == reward.totalQualifyingSessions && $0 != .homeCluster }
        return opened?.displayName ?? String(localized: "New world")
    }

    private func milestoneLine(_ planet: CelestialSnapshot) -> String {
        let ordinal = planet.ordinal.formatted(.number.notation(.automatic))
        let worldWord: String = switch planet.ordinal {
        case 1: String(localized: "Your first world.")
        case 2: String(localized: "Your second world.")
        case 3: String(localized: "Your third world.")
        default: String(localized: "World number \(ordinal).")
        }
        return worldWord + " " + String(localized: "\(reward.totalQualifyingSessions) sessions of light gathered into something you can visit forever.")
    }

    // MARK: Helpers

    private func rise<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(shown ? 1 : 0)
            .offset(y: shown || motion == .reduced ? 0 : 18)
            .animation(LMSpring.settle.delay(Double(index) * 0.08), value: shown)
    }

    private func checkNotificationPrompt() async {
        guard !app.preferences.hasSeenNotificationPrompt, reward.outcome != .tooShort else { return }
        let status = await app.notifications.authorizationStatus()
        if status == .notDetermined {
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(LMSpring.settle) { askNotifications = true }
        }
    }
}

private extension Color {
    /// Warm starlight at night; falls back to primary text at dawn.
    func blendedForScheme(_ light: Color) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(self) : UIColor(light)
        })
    }
}
