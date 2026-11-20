import SwiftData
import SwiftUI

/// Today's orbit: the day plan as a living route. A countdown to what's now
/// or next sits on top; below, the stops of the day wind from dawn to night,
/// lit ones burning as stars and a comet marking the present. Tapping a stop
/// shows its actions; focusing on it is one tap.
struct DayOrbitView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selectedID: UUID?
    @State private var editing: FocusTask?
    @State private var showPlanner = false
    @State private var plannerDay: Date?
    @State private var ignitions: [UUID: Date] = [:]
    @State private var litIDs: Set<UUID>?
    @State private var appeared = Date()

    var body: some View {
        DayPlanReader { scheduled in
            let today = scheduled.filter { task in
                task.scheduledStart.map { app.clock.calendar.isDate($0, inSameDayAs: app.clock.now) } ?? false
            }
            let blocks = today.compactMap(\.planBlock)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let timeline = DayTimeline(blocks: blocks, now: app.clock.now)
                content(timeline: timeline, tasks: today)
            }
            .onChange(of: Set(blocks.filter(\.isCompleted).map(\.id)), initial: true) { _, lit in
                // A stop lit while watching bursts into its star.
                if let before = litIDs {
                    for id in lit.subtracting(before) { ignitions[id] = .now }
                }
                litIDs = lit
            }
            .onAppear {
                Telemetry.log(.planOrbitOpened(blocks: blocks.count, lit: blocks.filter(\.isCompleted).count))
            }
        }
        .background { CosmicBackgroundView(mood: .home, light: 0.45, showsStars: true, starOpacity: 0.8) }
        .sheet(item: $editing) { task in
            BlockEditorView(task: task, day: task.scheduledStart ?? app.clock.now)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .sheet(isPresented: $showPlanner) {
            DayPlannerView(initialDay: plannerDay)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .onChange(of: app.timer.state.phase.isFocusActive) { _, active in
            // A session started elsewhere (Siri, the watch): make way for the focus screen.
            if active { app.isShowingDayOrbit = false }
        }
        .telemetryScreen("day_orbit")
    }

    @ViewBuilder
    private func content(timeline: DayTimeline, tasks: [FocusTask]) -> some View {
        VStack(spacing: 0) {
            topBar
            OrbitHero(timeline: timeline)
                .padding(.horizontal, LMSpace.l)
                .padding(.bottom, LMSpace.s)
            if timeline.blocks.isEmpty {
                emptyState
            } else {
                route(timeline: timeline)
            }
            HabitOrbitStrip()
            bottomPanel(timeline: timeline, tasks: tasks)
        }
        .readableColumn(640)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                app.isShowingDayOrbit = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LMColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("orbit.close")
            Spacer()
            VStack(spacing: 2) {
                Text("Today's orbit")
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(app.clock.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textTertiary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer()
            Button {
                plannerDay = nil
                showPlanner = true
            } label: {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(LMColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Plan your day"))
            .accessibilityIdentifier("orbit.plan")
        }
        .padding(.horizontal, LMSpace.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    // MARK: Route

    private func route(timeline: DayTimeline) -> some View {
        GeometryReader { geo in
            let route = OrbitRoute(width: geo.size.width, count: timeline.blocks.count,
                                   spacing: typeSize.isAccessibilitySize ? 190 : 132)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        OrbitRouteCanvas(blocks: timeline.blocks, route: route, selected: selectedID,
                                         ignitions: ignitions, appeared: appeared)
                        ForEach(Array(timeline.blocks.enumerated()), id: \.element.id) { k, block in
                            stopLabel(block, index: k, route: route, timeline: timeline)
                        }
                        ForEach(Array(zip(timeline.blocks, timeline.blocks.dropFirst()).enumerated()), id: \.offset) { k, pair in
                            gapLabel(after: pair.0, before: pair.1, index: k, route: route)
                        }
                    }
                    .frame(width: route.width, height: route.height)
                }
                .scrollIndicators(.hidden)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                             .init(color: .black, location: 0.93), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .onAppear {
                    appeared = .now
                    let target = max(0, min(timeline.blocks.count - 1, Int(timeline.cursor.rounded())))
                    proxy.scrollTo("stop-\(target)", anchor: .center)
                }
            }
        }
    }

    private func stopLabel(_ block: PlanBlock, index k: Int, route: OrbitRoute, timeline: DayTimeline) -> some View {
        let p = route.point(Double(k))
        let left = route.isLeft(k)
        let width = max(80, (left ? route.width - p.x : p.x) - 40 - LMSpace.m)
        let status = timeline.status(of: block)
        let tint = PlanFormat.color(for: status, category: block.category)
        return ZStack {
            Button {
                app.haptics.selection()
                withAnimation(LMSpring.snap) { selectedID = selectedID == block.id ? nil : block.id }
            } label: {
                Color.clear.frame(width: 64, height: 64).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(p)
            .accessibilityHidden(true)

            Button {
                app.haptics.selection()
                withAnimation(LMSpring.snap) { selectedID = selectedID == block.id ? nil : block.id }
            } label: {
                VStack(alignment: left ? .leading : .trailing, spacing: 3) {
                    Text(PlanFormat.range(block))
                        .font(LMFont.eyebrow.monospacedDigit())
                        .lmTracking(1)
                        .foregroundStyle(tint)
                    Text(block.title)
                        .font(LMFont.headline)
                        .foregroundStyle(status == .passed ? LMColor.textSecondary : LMColor.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(left ? .leading : .trailing)
                    Text(PlanFormat.status(block, in: timeline))
                        .font(LMFont.footnote.monospacedDigit())
                        .foregroundStyle(status == .active ? LMColor.calm : LMColor.textTertiary)
                }
                .frame(width: width, alignment: left ? .leading : .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: left ? p.x + 34 + width / 2 : p.x - 34 - width / 2, y: p.y)
            .accessibilityLabel(Text(PlanFormat.spoken(block, in: timeline)))
            .accessibilityHint(Text("Shows what you can do with this block"))
            .accessibilityAddTraits(selectedID == block.id ? [.isSelected] : [])
            .accessibilityIdentifier("orbit.stop.\(k)")

            Color.clear.frame(width: 1, height: 1).position(p).id("stop-\(k)")
        }
        .frame(width: route.width, height: route.height)
    }

    @ViewBuilder
    private func gapLabel(after a: PlanBlock, before b: PlanBlock, index k: Int, route: OrbitRoute) -> some View {
        let gap = b.start.timeIntervalSince(a.end)
        if gap >= 15 * 60 {
            // A little past the halfway point, on the side of the stop just
            // left behind: the route has swung to the other side by then.
            let mid = route.point(Double(k) + 0.6)
            let left = route.isLeft(k)
            Text("\(PlanFormat.span(gap)) free")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(LMColor.textPrimary.opacity(0.05)))
                .fixedSize()
                .position(x: route.center + (left ? -1 : 1) * route.amplitude * 0.62, y: mid.y)
                .frame(width: route.width, height: route.height)
                .accessibilityHidden(true)
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private func bottomPanel(timeline: DayTimeline, tasks: [FocusTask]) -> some View {
        let chosen = selectedID.flatMap { id in timeline.blocks.first { $0.id == id } } ?? timeline.focus
        VStack(spacing: LMSpace.s) {
            if let block = chosen, let task = tasks.first(where: { $0.id == block.id }) {
                StopActions(block: block, task: task, timeline: timeline, isPinned: selectedID != nil,
                            onEdit: { editing = task },
                            onUnpin: { withAnimation(LMSpring.snap) { selectedID = nil } })
            } else if timeline.isComplete {
                CosmicButton(title: "Plan tomorrow", systemImage: "moon.stars", kind: .secondary, height: 54) {
                    plannerDay = app.clock.calendar.date(byAdding: .day, value: 1, to: app.clock.now)
                    showPlanner = true
                }
                .accessibilityIdentifier("orbit.planTomorrow")
            } else if timeline.blocks.isEmpty {
                CosmicButton(title: "Plan your day", systemImage: "plus", kind: .starlight, height: 56) {
                    plannerDay = nil
                    showPlanner = true
                }
                .accessibilityIdentifier("orbit.planDay")
            }
        }
        .padding(.horizontal, LMSpace.l)
        .padding(.top, LMSpace.xs)
        .padding(.bottom, LMSpace.s)
        .animation(LMSpring.settle, value: chosen?.id)
    }

    private var emptyState: some View {
        FittingScrollView(alignment: .center) {
            VStack(spacing: LMSpace.m) {
                PellView(mood: .happy, showsLabel: false)
                Text("Map your day, hour by hour")
                    .font(LMFont.voice(.title))
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Each block you plan becomes a stop on today's orbit. Light them one by one.")
                    .font(LMFont.body)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LMSpace.l)
        }
    }
}

/// The countdown at the top of the orbit: what's now and how long it has
/// left, or what's next and how long until it begins.
struct OrbitHero: View {
    var timeline: DayTimeline
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: LMSpace.m) {
            VStack(alignment: .leading, spacing: 4) {
                EyebrowText(eyebrow, color: tint)
                Text(title)
                    .font(LMFont.voice(.title2))
                    .foregroundStyle(LMColor.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let target {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PlanFormat.countdown(target.timeIntervalSince(timeline.now)))
                            .font(LMFont.timer(size: typeSize.isAccessibilitySize ? 40 : 46))
                            .foregroundStyle(LMColor.textPrimary)
                            .contentTransition(.numericText(countsDown: true))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(timeline.current != nil ? String(localized: "left") : String(localized: "to go"))
                            .font(LMFont.callout)
                            .foregroundStyle(LMColor.textSecondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(spokenCountdown(target)))
                } else {
                    Text(subtitle)
                        .font(LMFont.callout.weight(.regular))
                        .foregroundStyle(LMColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !timeline.blocks.isEmpty, !typeSize.isAccessibilitySize {
                ZStack {
                    OrbitalProgressView(progress: ringProgress, lineWidth: 4, trackWidth: 3, headSize: 8)
                    VStack(spacing: 0) {
                        Text("\(timeline.litCount)/\(timeline.blocks.count)")
                            .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                            .foregroundStyle(LMColor.textPrimary)
                        Text("lit")
                            .font(LMFont.eyebrow)
                            .foregroundStyle(LMColor.reward)
                    }
                }
                .frame(width: 84, height: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(timeline.litCount) of \(timeline.blocks.count) blocks lit"))
            }
        }
        .padding(LMSpace.m)
        .glassCard(radius: 26, tint: timeline.current.map { _ in LMColor.calm })
        .accessibilityIdentifier("orbit.hero")
    }

    private var tint: Color {
        if timeline.current != nil { return LMColor.calm }
        if timeline.next != nil { return LMColor.focus }
        return LMColor.reward
    }

    private var target: Date? { timeline.current?.end ?? timeline.next?.start }

    private var ringProgress: Double {
        guard !timeline.blocks.isEmpty else { return 0 }
        return Double(timeline.litCount) / Double(timeline.blocks.count)
    }

    private var eyebrow: String {
        if let current = timeline.current { return String(localized: "Now · until \(PlanFormat.time(current.end))") }
        if let next = timeline.next { return String(localized: "Next · at \(PlanFormat.time(next.start))") }
        if timeline.blocks.isEmpty { return String(localized: "Nothing planned yet") }
        return String(localized: "Day complete")
    }

    private var title: String {
        if let block = timeline.current ?? timeline.next { return block.title }
        if timeline.blocks.isEmpty { return String(localized: "A blank sky") }
        return timeline.litCount == timeline.blocks.count
            ? String(localized: "Every stop is lit.") : String(localized: "Today's orbit is complete.")
    }

    private var subtitle: String {
        if timeline.blocks.isEmpty { return String(localized: "Plan a few blocks and follow them like a route.") }
        return String(localized: "\(timeline.litCount) of \(timeline.blocks.count) stops lit · \(LMFormat.minutes(timeline.plannedMinutes)) planned")
    }

    private func spokenCountdown(_ target: Date) -> String {
        let minutes = Int((target.timeIntervalSince(timeline.now) / 60).rounded(.up))
        return timeline.current != nil
            ? String(localized: "\(LMFormat.spokenMinutes(minutes)) left")
            : String(localized: "Begins in \(LMFormat.spokenMinutes(minutes))")
    }
}

/// What to do with one stop: focus on it (one tap), light it, edit it.
struct StopActions: View {
    var block: PlanBlock
    var task: FocusTask
    var timeline: DayTimeline
    var isPinned: Bool
    var onEdit: () -> Void
    var onUnpin: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let status = timeline.status(of: block)
        let planner = app.planner
        let usual = planner.focusMinutes(for: block, usual: app.preferences.defaultFocusMinutes)
        let whole = planner.wholeBlockMinutes(for: block)
        VStack(alignment: .leading, spacing: LMSpace.s) {
            HStack(spacing: LMSpace.s) {
                PlanStopGlyph(status: status, category: block.category, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .lineLimit(1)
                    Text("\(PlanFormat.range(block)) · \(PlanFormat.status(block, in: timeline))")
                        .font(LMFont.footnote.monospacedDigit())
                        .foregroundStyle(LMColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isPinned {
                    Button(action: onUnpin) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LMColor.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text("Back to what's next"))
                }
            }
            .accessibilityElement(children: .combine)

            AdaptiveStack(spacing: LMSpace.xs) {
                HStack(spacing: LMSpace.xs) {
                    RoundControlButton(systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark",
                                       label: task.isCompleted ? "Reopen" : "Mark as lit", size: 52, prominent: true) {
                        withAnimation(LMSpring.bloom) { app.tasks.setCompleted(task, !task.isCompleted) }
                        if !task.isCompleted { app.haptics.selection() } else { app.haptics.success() }
                    }
                    .accessibilityIdentifier("orbit.toggleLit")
                    RoundControlButton(systemImage: "pencil", label: "Edit block", size: 52, prominent: true, action: onEdit)
                        .accessibilityIdentifier("orbit.edit")
                }
                if !task.isCompleted {
                    Button {
                        app.requestPlanFocus(block.id, minutes: usual, source: "orbit")
                    } label: {
                        HStack(spacing: LMSpace.xs) {
                            if !typeSize.isAccessibilitySize { Image(systemName: "sparkle") }
                            Text("Begin focus · \(usual) min")
                        }
                    }
                    .buttonStyle(CosmicButtonStyle(kind: .reward, height: 52))
                    .accessibilityIdentifier("orbit.focus")
                }
            }
            if !task.isCompleted, whole > usual {
                Button {
                    app.requestPlanFocus(block.id, minutes: whole, source: "orbit_whole")
                } label: {
                    Text("Or focus through the whole block · \(LMFormat.minutes(whole))")
                        .font(LMFont.footnote)
                        .foregroundStyle(LMColor.textSecondary)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("orbit.focusWhole")
            }
        }
        .padding(LMSpace.m)
        .glassCard(radius: 26, tint: status == .active ? LMColor.calm : nil)
    }
}
