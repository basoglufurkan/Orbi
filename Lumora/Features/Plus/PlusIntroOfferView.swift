import SwiftUI

/// Shown once, right after onboarding (or after a universe comes back from
/// iCloud on a new install): the yearly plan laid out as a
/// timeline. With a free trial to give: today, the reminder, the first
/// charge. Without one (already used, or none set up): today, the renewal,
/// cancelling. Closing it offers Orbi+ for life once; closing that too
/// leaves Orbi+ to the regular paywall. With nothing for sale it quietly closes.
struct PlusIntroOfferView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .trial
    @State private var isBuying = false
    @State private var message: String?
    @State private var openedAt = Date()
    @State private var purchased = false
    @State private var loaded = false

    enum Step { case trial, lifetime }

    private var source: String {
        guard step == .trial else { return "onboarding_lifetime" }
        return app.plus.plans.first { $0.kind == .yearly }?.trialDays == nil ? "onboarding_yearly" : "onboarding_trial"
    }

    var body: some View {
        let store = app.plus
        let yearly = store.plans.first { $0.kind == .yearly }
        let lifetime = store.plans.first { $0.kind == .lifetime }
        ZStack {
            CosmicBackgroundView(mood: .reward, light: 0.6, starOpacity: 0.9)
            if !loaded {
                ProgressView().tint(LMColor.textSecondary)
            } else if step == .trial, let yearly {
                Group {
                    if let days = yearly.trialDays { trialPage(yearly, days: days) } else { yearlyPage(yearly) }
                }
                .transition(.opacity)
            } else if let lifetime {
                lifetimePage(lifetime)
                    .transition(.opacity)
            }
        }
        .task {
            await store.loadPlans()
            await store.syncOwnedPurchases()
            loaded = true
            guard !store.isActive, !store.plans.isEmpty else { return dismiss() }
            // No yearly plan to lead with: straight to lifetime, or out.
            if !store.plans.contains(where: { $0.kind == .yearly }) {
                guard store.plans.contains(where: { $0.kind == .lifetime }) else { return dismiss() }
                step = .lifetime
            }
            logViewed(store)
        }
        .alert(String(localized: "Orbi+"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .accessibilityIdentifier("plus.introOffer")
        .telemetryScreen("intro_offer")
    }

    // MARK: Trial

    private func trialPage(_ plan: PlusPlan, days: Int) -> some View {
        let start = Date()
        let chargeDate = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let reminderDay = Self.reminderDay(trialDays: days)
        return page(close: { moveOn() }) {
            VStack(spacing: LMSpace.s) {
                PlusGlyph()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Try Orbi+ free for \(days) days")
                    .font(LMFont.voice(.largeTitle))
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Nothing to pay today. Cancel anytime before the trial ends.")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                TimelineRow(symbol: "lock.open.fill", title: String(localized: "Today"),
                            detail: String(localized: "Sky themes, every soundscape and your whole history open up."),
                            isFirst: true)
                TimelineRow(symbol: "bell.fill", title: String(localized: "Day \(reminderDay): a reminder"),
                            detail: String(localized: "We'll let you know two days before your trial ends."))
                TimelineRow(symbol: "sparkle", title: String(localized: "Day \(days): your plan begins"),
                            detail: String(localized: "You'll be charged \(plan.price) on \(chargeDate.formatted(date: .long, time: .omitted)) unless you cancel before."),
                            isLast: true)
            }
            .padding(LMSpace.m)
            .glassCard()
        } footer: {
            Text("Free for \(days) days, then \(plan.price) a year. Renews automatically; cancel anytime in Settings.")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            buyButton(String(localized: "Start my free trial"), plan: plan)
            Button(String(localized: "Not now")) { moveOn() }
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("plus.introOffer.notNow")
        }
    }

    // MARK: Yearly, no trial

    private func yearlyPage(_ plan: PlusPlan) -> some View {
        let renewal = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        return page(close: { moveOn() }) {
            VStack(spacing: LMSpace.s) {
                PlusGlyph()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("A year of Orbi+")
                    .font(LMFont.voice(.largeTitle))
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Everything Orbi+ adds, for \(plan.price) a year.")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                TimelineRow(symbol: "lock.open.fill", title: String(localized: "Today"),
                            detail: String(localized: "Sky themes, every soundscape and your whole history open up."),
                            isFirst: true)
                TimelineRow(symbol: "arrow.clockwise", title: String(localized: "In a year"),
                            detail: String(localized: "Your plan renews on \(renewal.formatted(date: .long, time: .omitted)) for \(plan.price)."))
                TimelineRow(symbol: "hand.raised.fill", title: String(localized: "Anytime"),
                            detail: String(localized: "Cancel in Settings › Apple Account › Subscriptions. Orbi+ stays until the year you paid for ends."),
                            isLast: true)
            }
            .padding(LMSpace.m)
            .glassCard()
        } footer: {
            Text("\(plan.price) a year. Renews automatically; cancel anytime in Settings.")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            buyButton(String(localized: "Continue"), plan: plan)
            Button(String(localized: "Not now")) { moveOn() }
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("plus.introOffer.notNow")
        }
    }

    // MARK: Lifetime

    private func lifetimePage(_ plan: PlusPlan) -> some View {
        page(close: { dismiss() }) {
            VStack(spacing: LMSpace.s) {
                Text("Rather not subscribe?")
                    .font(LMFont.eyebrow)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(LMColor.calm)
                PlusGlyph()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
                Text("Keep Orbi+ forever")
                    .font(LMFont.voice(.largeTitle))
                    .foregroundStyle(LMColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Pay once and every Orbi+ feature is yours, now and in every update.")
                    .font(LMFont.callout)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: LMSpace.xs) {
                Text(plan.price)
                    .font(LMFont.voice(.largeTitle))
                    .foregroundStyle(LMColor.reward)
                Text("One payment. No subscription, no renewals.")
                    .font(LMFont.footnote)
                    .foregroundStyle(LMColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(LMSpace.l)
            .glassCard(border: LMColor.rewardFill.opacity(0.6))

            VStack(alignment: .leading, spacing: LMSpace.s) {
                ForEach(PlusFeature.allCases) { feature in
                    HStack(spacing: LMSpace.s) {
                        Image(systemName: feature.symbol)
                            .foregroundStyle(LMColor.reward)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text(feature.title).font(LMFont.callout).foregroundStyle(LMColor.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LMSpace.m)
            .glassCard()
        } footer: {
            Text("One payment of \(plan.price). No subscription.")
                .font(LMFont.footnote)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
            buyButton(String(localized: "Unlock forever"), plan: plan)
            Button(String(localized: "No thanks")) { dismiss() }
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textSecondary)
                .frame(minHeight: 44)
                .accessibilityIdentifier("plus.introOffer.noThanks")
        }
    }

    // MARK: Pieces

    /// A scrolling page with a close button and a pinned footer.
    private func page<Content: View, Footer: View>(close: @escaping () -> Void,
                                                   @ViewBuilder content: () -> Content,
                                                   @ViewBuilder footer: () -> Footer) -> some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: LMSpace.l) { content() }
                    .padding(.horizontal, LMSpace.l)
                    .padding(.top, LMSpace.xxl)
                    .padding(.bottom, LMSpace.l)
                    .readableColumn(560)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: LMSpace.xs) {
                    footer()
                    legalLinks
                }
                .padding(.horizontal, LMSpace.l)
                .padding(.top, LMSpace.s)
                .readableColumn(560)
                .background(
                    LinearGradient(colors: [LMColor.bgBase.opacity(0), LMColor.bgBase, LMColor.bgBase],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.top, -LMSpace.l)
                        .ignoresSafeArea())
            }
            RoundControlButton(systemImage: "xmark", label: "Close", size: 44, action: close)
                .padding(LMSpace.m)
                .accessibilityIdentifier("plus.introOffer.close")
        }
    }

    private func buyButton(_ title: String, plan: PlusPlan) -> some View {
        Button {
            Task { await buy(plan) }
        } label: {
            if isBuying { ProgressView().tint(LMColor.onAccent) } else { Text(title) }
        }
        .buttonStyle(CosmicButtonStyle(kind: .reward))
        .disabled(isBuying)
        .accessibilityIdentifier("plus.introOffer.buy")
    }

    private var legalLinks: some View {
        HStack(spacing: LMSpace.m) {
            Link(String(localized: "Terms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link(String(localized: "Privacy"), destination: URL(string: "https://www.mobapptech.com/lumora-privacy-policy/")!)
        }
        .font(LMFont.footnote)
        .foregroundStyle(LMColor.textTertiary)
        .tint(LMColor.textTertiary)
    }

    // MARK: Actions

    /// From the trial to the lifetime offer, or out if there's no lifetime plan.
    private func moveOn() {
        logDismissed()
        guard app.plus.plans.contains(where: { $0.kind == .lifetime }) else { return dismiss() }
        withAnimation(.easeInOut(duration: 0.45)) { step = .lifetime }
        logViewed(app.plus)
    }

    private func buy(_ plan: PlusPlan) async {
        isBuying = true
        defer { isBuying = false }
        do {
            switch try await app.plus.purchase(plan, source: source) {
            case .purchased:
                purchased = true
                app.haptics.success()
                if let days = plan.trialDays { await app.scheduleTrialReminder(trialDays: days, price: plan.price) }
                logDismissed()
                dismiss()
            case .pending:
                message = String(localized: "Your purchase is waiting for approval. Orbi+ turns on as soon as it's approved.")
            case .cancelled:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func logViewed(_ store: PlusStore) {
        openedAt = Date()
        Telemetry.log(.paywallViewed(source: source, feature: nil, plans: store.plans.count,
                                     availability: "\(store.availability)"))
    }

    private func logDismissed() {
        Telemetry.log(.paywallDismissed(source: source, seconds: Int(Date().timeIntervalSince(openedAt)),
                                        purchased: purchased))
    }

    /// The reminder comes two days before the first charge (day 5 of 7).
    static func reminderDay(trialDays: Int) -> Int { max(1, trialDays - 2) }
}

/// One stop on the trial timeline: an icon on a golden line, a title and a line of detail.
private struct TimelineRow: View {
    var symbol: String
    var title: String
    var detail: String
    var isFirst = false
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: LMSpace.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(LMColor.onAccent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(LMColor.rewardFill))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                Text(detail).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 10)
            .padding(.bottom, isLast ? 0 : LMSpace.l)
            Spacer(minLength: 0)
        }
        // The line joining the stops runs behind the icons, sized by the row.
        .background(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear.frame(height: isFirst ? 20 : 0)
                if isLast {
                    LMColor.rewardFill.opacity(0.5).frame(height: 20)
                    Spacer(minLength: 0)
                } else {
                    LMColor.rewardFill.opacity(0.5)
                }
            }
            .frame(width: 3)
            .padding(.leading, 18.5)
        }
        .accessibilityElement(children: .combine)
    }
}
