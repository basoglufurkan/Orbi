import Charts
import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Insights: gentle reflection, not a productivity dashboard. Swift Charts
/// for the daily bars, with accessible labels and friendly empty states.
struct InsightsView: View {
    @Environment(AppModel.self) private var app
    @State private var period: InsightsModel.Period = .week
    @State private var showYear = false
    /// Whole periods back; going back past this week or month is Orbi+.
    @State private var offset = 0
    @State private var paywall: PlusFeature?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        StatsReader { stats, facts in
            let model = InsightsModel.make(facts: facts, period: period, today: app.today,
                                           calendar: app.clock.calendar, now: app.clock.now,
                                           offset: app.plus.isActive ? offset : 0)
            ZStack {
                CosmicBackgroundView(mood: .home, light: 0.3, starOpacity: 0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: LMSpace.m) {
                        AdaptiveStack(spacing: LMSpace.s) {
                            Text("Insights")
                                .font(LMFont.largeTitle)
                                .foregroundStyle(LMColor.textPrimary)
                                .lineLimit(1)
                                .fixedSize()
                                .accessibilityAddTraits(.isHeader)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: LMSpace.s) }
                            CosmicSegmented(options: [(InsightsModel.Period.week, String(localized: "Week")),
                                                      (InsightsModel.Period.month, String(localized: "Month"))],
                                            selection: $period)
                                .frame(maxWidth: typeSize.isAccessibilitySize ? nil : 190)
                        }
                        .padding(.top, LMSpace.m)

                        if facts.filter(\.qualifies).isEmpty {
                            emptyState
                            // What there is to find, before the first is found.
                            CollectionLinkCard()
                        } else {
                            periodNavigator(model)
                            headlineCard(model)
                            yearCard(facts: facts)
                            statCards(stats)
                            CollectionLinkCard()
                            if period == .month { weeklyTotals(model) }
                            categoryCard(model)
                            monthSky(model)
                            SessionHistoryList(facts: facts)
                            exportButton(facts: facts)
                        }
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .readableColumn()
                }
                .statusBarScrim()
            }
            .plusPaywall($paywall, screen: "insights")
            .onChange(of: period) { _, now in
                offset = 0
                Telemetry.log(.insightsPeriodChanged(period: now == .week ? "week" : "month"))
            }
            .onChange(of: offset) { _, back in
                if back > 0 { Telemetry.log(.insightsHistoryBrowsed(period: period == .week ? "week" : "month", back: back)) }
            }
        }
    }

    // MARK: Earlier periods (Orbi+)

    private func periodNavigator(_ model: InsightsModel) -> some View {
        HStack(spacing: LMSpace.s) {
            navButton("chevron.backward", label: period == .week ? "Previous week" : "Previous month",
                      enabled: model.hasEarlier, id: "insights.previous") {
                guard app.plus.isActive else { return paywall = .history }
                withAnimation(LMSpring.settle) { offset += 1 }
            }
            Spacer(minLength: 0)
            HStack(spacing: LMSpace.xs) {
                Text(periodTitle(model))
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
                    .contentTransition(.numericText())
                if !app.plus.isActive, model.hasEarlier { PlusBadge() }
            }
            Spacer(minLength: 0)
            navButton("chevron.forward", label: period == .week ? "Next week" : "Next month",
                      enabled: model.offset > 0, id: "insights.next") {
                withAnimation(LMSpring.settle) { offset = max(0, offset - 1) }
            }
        }
    }

    private func navButton(_ symbol: String, label: LocalizedStringKey, enabled: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            app.haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(LMColor.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LMColor.textPrimary.opacity(0.06)))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }

    private func periodTitle(_ model: InsightsModel) -> String {
        switch (period, model.offset) {
        case (.week, 0): String(localized: "This week")
        case (.month, 0): String(localized: "This month")
        case (.week, _):
            "\(model.rangeStart.formatted(.dateTime.day().month(.abbreviated))) – \(model.rangeEnd.formatted(.dateTime.day().month(.abbreviated)))"
        case (.month, _): model.rangeStart.formatted(.dateTime.month(.wide).year())
        }
    }

    @ViewBuilder
    private func exportButton(facts: [SessionFacts]) -> some View {
        let label = HStack(spacing: LMSpace.xs) {
            Image(systemName: "tablecells")
            Text("Export sessions as CSV")
            if !app.plus.isActive { PlusBadge() }
        }
        if app.plus.isActive {
            ShareLink(item: SessionsCSV(text: InsightsModel.csv(facts: facts)),
                      preview: SharePreview(String(localized: "Orbi sessions"))) { label }
                .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 52))
                .simultaneousGesture(TapGesture().onEnded { Telemetry.log(.csvExported(sessions: facts.count)) })
                .accessibilityIdentifier("insights.export")
        } else {
            Button {
                app.haptics.selection()
                paywall = .export
            } label: { label }
                .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 52))
                .accessibilityIdentifier("insights.export")
        }
    }

    // MARK: Year in review

    /// "Your year in light": the year so far as a story you can share.
    private func yearCard(facts: [SessionFacts]) -> some View {
        let calendar = app.clock.calendar
        let year = calendar.component(.year, from: app.clock.now)
        let snap = app.odyssey.snapshot
        let review = YearReview.make(year: year, facts: facts, calendar: calendar, worlds: snap.worlds,
                                     events: snap.witnessedEvents, rank: snap.rank, horizons: snap.horizonsAchieved)
        return Button {
            app.haptics.selection()
            Telemetry.log(.yearReviewOpened(sessions: review.sessions))
            showYear = true
        } label: {
            HStack(spacing: LMSpace.m) {
                Image(systemName: "sparkles.rectangle.stack").font(.title2).foregroundStyle(LMColor.reward)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(String(localized: "Your year in light"), color: LMColor.reward)
                    Text("\(String(year)), told in stars").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").foregroundStyle(LMColor.reward)
            }
            .padding(LMSpace.m)
            .glassCard(border: LMColor.rewardFill.opacity(0.35))
        }
        .buttonStyle(PressScaleStyle())
        .opacity(review.hasContent ? 1 : 0)
        .disabled(!review.hasContent)
        .accessibilityIdentifier("insights.year")
        // Opened from a link; with nothing to tell yet, Insights itself is the answer.
        .task(id: app.pendingYearInReview) {
            guard app.pendingYearInReview else { return }
            app.pendingYearInReview = false
            if review.hasContent { showYear = true }
        }
        .fullScreenCover(isPresented: $showYear) {
            UniverseSceneReader { scene in
                YearInReviewView(review: review, scene: scene)
            }
        }
    }

    // MARK: Headline + chart

    private func headlineCard(_ model: InsightsModel) -> some View {
        let goal = app.preferences.dailyGoalMinutes
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            Text(headline(model))
                .font(LMFont.voice(.title))
                .foregroundStyle(LMColor.textPrimary)
            if let sentence = observation(model) {
                Text(sentence)
                    .font(LMFont.callout.weight(.regular))
                    .foregroundStyle(LMColor.textSecondary)
            }
            Chart {
                ForEach(model.bars) { bar in
                    BarMark(x: .value("Day", bar.date, unit: .day),
                            y: .value("Minutes", max(bar.minutes, bar.isRest ? 0 : 0)))
                        .foregroundStyle(bar.isToday
                                         ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xD8FBFF), Color(hex: Palette.starlightCyan)], startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xA99DFF), Color(hex: 0x7465E8)], startPoint: .top, endPoint: .bottom)))
                        .clipShape(RoundedRectangle(cornerRadius: period == .week ? 12 : 3, style: .continuous))
                        .accessibilityLabel(Text(bar.date.formatted(.dateTime.weekday(.wide).month().day())))
                        .accessibilityValue(Text(bar.isRest ? String(localized: "Rest day") : LMFormat.spokenMinutes(bar.minutes)))
                        .annotation(position: .top) {
                            if bar.isRest, period == .week {
                                Image(systemName: "moon").font(.caption).foregroundStyle(LMColor.calm)
                            }
                        }
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(LMColor.reward.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(LMFormat.minutes(goal))").font(LMFont.footnote).foregroundStyle(LMColor.reward)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: period == .week ? .dateTime.weekday(.narrow) : .dateTime.day(), centered: true)
                        .foregroundStyle(LMColor.textTertiary)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 220)
        }
        .padding(LMSpace.l)
        .glassCard()
    }

    private func headline(_ model: InsightsModel) -> String {
        let hours = Double(model.totalMinutes) / 60
        let span = switch (period, model.offset) {
        case (.week, 0): String(localized: "this week")
        case (.month, 0): String(localized: "this month")
        case (.week, _): String(localized: "that week")
        case (.month, _): String(localized: "that month")
        }
        if hours >= 1 {
            let h = hours >= 10 ? String(Int(hours.rounded())) : hours.formatted(.number.precision(.fractionLength(0...1)))
            return String(localized: "\(h) hours of light \(span).")
        }
        return String(localized: "\(model.totalMinutes) minutes of light \(span).")
    }

    private func observation(_ model: InsightsModel) -> String? {
        var parts: [String] = []
        if let part = model.steadiestPart { parts.append(String(localized: "Your steadiest focus happens \(part).")) }
        if let rest = model.restDayNames.last, period == .week {
            parts.append(String(localized: "\(rest) was a rest day — rhythm kept."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Cards

    private func statCards(_ stats: ProgressStats) -> some View {
        let longest = stats.longestSession
        let rhythmIsBest = stats.currentRhythm.days > 0 && stats.currentRhythm.days >= stats.longestRhythm
        return AdaptiveStack(spacing: LMSpace.s) {
            StatisticsCardView(title: String(localized: "Longest"), value: String(localized: "\(stats.longestSessionSeconds / 60) min"),
                               detail: longest.map { "\(LMFormat.shortDate($0.endedAt)) · \($0.category.displayName)" }, fillsHeight: true)
            StatisticsCardView(title: String(localized: "Best day"), value: LMFormat.minutes(stats.bestDaySeconds / 60),
                               detail: stats.bestDay?.startDate(calendar: app.clock.calendar).map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) },
                               fillsHeight: true)
            StatisticsCardView(title: String(localized: "Rhythm"), value: String(localized: "\(stats.currentRhythm.days) days"),
                               detail: rhythmIsBest ? String(localized: "Your longest yet") : String(localized: "Longest \(stats.longestRhythm)"),
                               highlight: rhythmIsBest ? LMColor.reward : nil, fillsHeight: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func weeklyTotals(_ model: InsightsModel) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            Text("Weekly totals").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            AdaptiveStack(spacing: LMSpace.xs) {
                ForEach(model.weekTotals) { w in
                    AdaptiveStackItem {
                        Text(LMFormat.minutes(w.minutes)).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                        Text(LMFormat.shortDate(w.start)).font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(LMSpace.l)
        .glassCard()
    }

    private func categoryCard(_ model: InsightsModel) -> some View {
        VStack(alignment: .leading, spacing: LMSpace.m) {
            Text("Where your light went").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            if model.categories.isEmpty {
                Text("No focus in this period yet.").font(LMFont.callout).foregroundStyle(LMColor.textSecondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(model.categories) { share in
                            Capsule().fill(share.category.color)
                                .frame(width: max(6, (geo.size.width - CGFloat(model.categories.count - 1) * 3) * share.fraction))
                        }
                    }
                }
                .frame(height: 18)
                .accessibilityHidden(true)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: LMSpace.s) {
                    ForEach(model.categories) { share in
                        HStack(spacing: 8) {
                            CategoryGlyph(category: share.category, size: 14)
                            Text(share.category.displayName).font(LMFont.callout).foregroundStyle(LMColor.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 4)
                            Text("\(Int((share.fraction * 100).rounded()))%").font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                                .fixedSize()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(LMSpace.l)
        .glassCard()
    }

    private func monthSky(_ model: InsightsModel) -> some View {
        let calendar = app.clock.calendar
        let leading = ((model.monthGrid.first.map { calendar.component(.weekday, from: $0.date) } ?? 1) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        return VStack(alignment: .leading, spacing: LMSpace.s) {
            AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: 4) {
                Text("\(model.monthName) sky").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
                if !typeSize.isAccessibilitySize { Spacer() }
                Text("brighter = more focus").font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 30) }
                ForEach(model.monthGrid) { day in
                    let brightness = model.maxMonthMinutes > 0 ? Double(day.minutes) / Double(model.maxMonthMinutes) : 0
                    ZStack {
                        Circle()
                            .fill(day.minutes > 0 ? LMColor.focus.opacity(0.18 + 0.82 * brightness) : LMColor.textPrimary.opacity(0.05))
                            .shadow(color: LMColor.focus.opacity(brightness * 0.8), radius: 6 * brightness)
                        if day.isToday { Circle().strokeBorder(LMColor.calm, lineWidth: 1.5) }
                    }
                    .frame(height: 30)
                    .accessibilityElement()
                    .accessibilityLabel(Text(day.date.formatted(.dateTime.month().day())))
                    .accessibilityValue(Text(LMFormat.spokenMinutes(day.minutes)))
                }
            }
        }
        .padding(LMSpace.l)
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: LMSpace.m) {
            PellView(mood: .curious, showsLabel: false)
                .padding(.vertical, LMSpace.m)
            Text("Your insights will gather here.")
                .font(LMFont.voice(.title))
                .foregroundStyle(LMColor.textPrimary)
            Text("Finish a session and Orbi will start reflecting your light back to you — gently, never as a scoreboard.")
                .font(LMFont.body)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            CosmicButton(title: "Begin Focus", systemImage: "sparkle") { app.timer.prepare() }
        }
        .padding(.vertical, LMSpace.xl)
    }
}

/// The way into the Collection: how many cosmic artifacts are found, with
/// the latest one beside it.
struct CollectionLinkCard: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \AchievementUnlock.unlockedAt, order: .reverse) private var unlocks: [AchievementUnlock]

    var body: some View {
        let earned = Set(unlocks.map(\.achievementID)).count
        let latest = unlocks.first?.definition
        Button {
            app.haptics.selection()
            app.isShowingCollection = true
        } label: {
            HStack(spacing: LMSpace.m) {
                Group {
                    if let latest {
                        ArtifactMotifView(motif: latest.motif, earned: true)
                    } else {
                        Image(systemName: "diamond")
                            .font(.title2)
                            .foregroundStyle(LMColor.reward)
                    }
                }
                .frame(width: 52, height: 44)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(String(localized: "Collection"), color: LMColor.reward)
                    Text("\(earned) of \(AchievementCatalog.all.count) cosmic artifacts found")
                        .font(LMFont.headline)
                        .foregroundStyle(LMColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(LMColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(LMSpace.m)
            .glassCard()
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityIdentifier("insights.collection")
    }
}

/// Recent sessions, newest first.
struct SessionHistoryList: View {
    var facts: [SessionFacts]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: LMSpace.s) {
            Text("Session history").font(LMFont.title).foregroundStyle(LMColor.textPrimary)
            ForEach(facts.reversed().prefix(25), id: \.id) { s in
                HStack(spacing: LMSpace.s) {
                    CategoryGlyph(category: s.category, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.intention.isEmpty ? s.category.displayName : s.intention)
                            .font(LMFont.headline.weight(.medium))
                            .foregroundStyle(LMColor.textPrimary)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        Text("\(s.endedAt.formatted(.dateTime.month(.abbreviated).day())) · \(LMFormat.time(s.startedAt)) · \(outcomeLabel(s.outcome))")
                            .font(LMFont.footnote)
                            .foregroundStyle(LMColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text("\(s.focusedMinutes)m").font(LMFont.headline).foregroundStyle(LMColor.textSecondary)
                        .fixedSize()
                }
                .padding(.horizontal, LMSpace.m)
                .padding(.vertical, LMSpace.s)
                .glassCard(radius: LMRadius.row)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func outcomeLabel(_ o: SessionOutcome) -> String {
        switch o {
        case .completed: String(localized: "Completed")
        case .endedEarly: String(localized: "Ended early")
        case .tooShort: String(localized: "Short pause")
        }
    }
}

/// Every session as a spreadsheet file, for the share sheet.
struct SessionsCSV: Transferable {
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName("Orbi sessions.csv")
    }
}
