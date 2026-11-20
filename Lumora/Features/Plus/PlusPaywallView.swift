import StoreKit
import SwiftUI

/// The Orbi+ paywall. Gentle by design: it says what's added, keeps the
/// free promise visible, and never blocks the universe itself.
struct PlusPaywallView: View {
    /// The locked thing that was tapped, shown first.
    var feature: PlusFeature?
    /// Where it was opened from, for analytics: settings, locked_feature, link, third_star.
    var source: String = "settings"

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PlusPlan.Kind = .yearly
    @State private var isBuying = false
    @State private var isRestoring = false
    @State private var message: String?
    @State private var showManage = false
    @State private var openedAt = Date()
    @State private var purchased = false
    @State private var loggedView = false

    var body: some View {
        let store = app.plus
        ZStack(alignment: .topTrailing) {
            CosmicBackgroundView(mood: .reward, light: 0.6, starOpacity: 0.9)
            ScrollView {
                VStack(spacing: LMSpace.l) {
                    hero(active: store.isActive)
                    if store.isActive {
                        activeCard(store)
                    } else {
                        plansSection(store)
                    }
                    featureList
                    freePromise
                    links(store)
                }
                .padding(.horizontal, LMSpace.l)
                .padding(.top, LMSpace.l)
                .padding(.bottom, LMSpace.l)
                .readableColumn(560)
            }
            .scrollIndicators(.hidden)
            // The button and its terms stay in reach however far the list scrolls.
            .safeAreaInset(edge: .bottom) {
                if !store.isActive {
                    VStack(spacing: LMSpace.xs) {
                        buyButton(store)
                        finePrint(store)
                    }
                    .padding(.horizontal, LMSpace.l)
                    .padding(.top, LMSpace.s)
                    .padding(.bottom, LMSpace.xs)
                    .readableColumn(560)
                    .background(
                        LinearGradient(colors: [LMColor.bgBase.opacity(0), LMColor.bgBase, LMColor.bgBase],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.top, -LMSpace.l)
                            .ignoresSafeArea())
                }
            }
            RoundControlButton(systemImage: "xmark", label: "Close", size: 44) { dismiss() }
                .padding(LMSpace.m)
                .accessibilityIdentifier("plus.close")
        }
        .task {
            await store.loadPlans()
            // Once per showing, after plans load, so "plans" says what the person saw.
            guard !loggedView else { return }
            loggedView = true
            openedAt = Date()
            Telemetry.log(.paywallViewed(source: source, feature: feature?.rawValue, plans: store.plans.count,
                                         availability: store.isActive ? "already_plus" : "\(store.availability)"))
        }
        .onDisappear {
            Telemetry.log(.paywallDismissed(source: source, seconds: Int(Date().timeIntervalSince(openedAt)),
                                            purchased: purchased))
        }
        .onChange(of: store.plans) { _, plans in
            if !plans.contains(where: { $0.kind == selected }), let first = plans.first { selected = first.kind }
        }
        .alert(String(localized: "Orbi+"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .accessibilityIdentifier("plus.paywall")
        .telemetryScreen("paywall")
    }

    // MARK: Sections

    private func hero(active: Bool) -> some View {
        VStack(spacing: LMSpace.s) {
            PlusGlyph()
                .frame(width: 80, height: 80)
                .padding(.bottom, LMSpace.xs)
                .accessibilityHidden(true)
            Text("Orbi+")
                .font(LMFont.voice(.largeTitle))
                .foregroundStyle(LMColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(active ? String(localized: "Thank you. Your sky has everything it can hold.")
                        : String(localized: "More ways to make your universe your own."))
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var featureList: some View {
        let ordered = feature.map { f in [f] + PlusFeature.allCases.filter { $0 != f } } ?? PlusFeature.allCases
        return VStack(alignment: .leading, spacing: LMSpace.m) {
            ForEach(ordered) { item in
                HStack(alignment: .top, spacing: LMSpace.s) {
                    Image(systemName: item.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(item == feature ? LMColor.onAccent : LMColor.reward)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(item == feature ? LMColor.rewardFill : LMColor.rewardFill.opacity(0.14)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                        Text(item.detail).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(LMSpace.m)
        .glassCard()
    }

    @ViewBuilder
    private func plansSection(_ store: PlusStore) -> some View {
        switch store.availability {
        case .loading where store.plans.isEmpty:
            ProgressView()
                .tint(LMColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .unavailable where store.plans.isEmpty:
            Text("The App Store isn't reachable right now. Try again in a moment.")
                .font(LMFont.callout)
                .foregroundStyle(LMColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 120)
        default:
            VStack(spacing: LMSpace.s) {
                ForEach(store.plans) { plan in
                    PlanCard(plan: plan, savings: plan.kind == .yearly ? store.yearlySavings : nil,
                             isSelected: plan.kind == selected) {
                        app.haptics.selection()
                        withAnimation(LMSpring.snap) { selected = plan.kind }
                        Telemetry.log(.paywallPlanSelected(plan: plan.kind.rawValue))
                    }
                }
            }
        }
    }

    private func buyButton(_ store: PlusStore) -> some View {
        let plan = store.plans.first { $0.kind == selected }
        let title: String = if let days = plan?.trialDays {
            String(localized: "Start \(days)-day free trial")
        } else if plan?.kind == .lifetime {
            String(localized: "Unlock forever")
        } else {
            String(localized: "Continue")
        }
        return Button {
            guard let plan else { return }
            Task { await buy(plan) }
        } label: {
            if isBuying {
                ProgressView().tint(LMColor.onAccent)
            } else {
                Text(title)
            }
        }
        .buttonStyle(CosmicButtonStyle(kind: .reward))
        .disabled(plan == nil || isBuying || isRestoring)
        .accessibilityIdentifier("plus.buy")
    }

    @ViewBuilder
    private func finePrint(_ store: PlusStore) -> some View {
        if let plan = store.plans.first(where: { $0.kind == selected }) {
            Group {
                switch plan.kind {
                case .lifetime:
                    Text("One payment of \(plan.price). No subscription.")
                case .yearly:
                    if let days = plan.trialDays {
                        Text("Free for \(days) days, then \(plan.price) a year. Renews automatically; cancel anytime in Settings.")
                    } else {
                        Text("\(plan.price) a year. Renews automatically; cancel anytime in Settings.")
                    }
                case .monthly:
                    if let days = plan.trialDays {
                        Text("Free for \(days) days, then \(plan.price) a month. Renews automatically; cancel anytime in Settings.")
                    } else {
                        Text("\(plan.price) a month. Renews automatically; cancel anytime in Settings.")
                    }
                }
            }
            .font(LMFont.footnote)
            .foregroundStyle(LMColor.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func activeCard(_ store: PlusStore) -> some View {
        VStack(spacing: LMSpace.s) {
            Label(String(localized: "Orbi+ is on"), systemImage: "checkmark.seal.fill")
                .font(LMFont.headline)
                .foregroundStyle(LMColor.reward)
            if store.isLifetime {
                Text("Yours for good.").font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
            } else if let date = store.renewalDate {
                Text("Renews on \(date.formatted(date: .long, time: .omitted)).")
                    .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
            }
            if !store.isLifetime {
                Button(String(localized: "Manage subscription")) {
                    Telemetry.log(.manageSubscriptionOpened)
                    showManage = true
                }
                    .buttonStyle(CosmicButtonStyle(kind: .secondary, height: 48))
                    .padding(.top, LMSpace.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(LMSpace.m)
        .glassCard(border: LMColor.rewardFill.opacity(0.4))
    }

    private var freePromise: some View {
        Text("Stars, your universe, the Odyssey and focusing together stay free. Stardust is never sold.")
            .font(LMFont.footnote)
            .foregroundStyle(LMColor.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func links(_ store: PlusStore) -> some View {
        HStack(spacing: LMSpace.m) {
            if !store.isActive {
                Button {
                    Task { await restore() }
                } label: {
                    if isRestoring { ProgressView() } else { Text("Restore purchases") }
                }
                .disabled(isBuying || isRestoring)
                .accessibilityIdentifier("plus.restore")
            }
            Link(String(localized: "Terms"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link(String(localized: "Privacy"), destination: URL(string: "https://www.mobapptech.com/lumora-privacy-policy/")!)
        }
        .font(LMFont.footnote)
        .foregroundStyle(LMColor.textSecondary)
        .tint(LMColor.textSecondary)
    }

    // MARK: Actions

    private func buy(_ plan: PlusPlan) async {
        isBuying = true
        defer { isBuying = false }
        do {
            switch try await app.plus.purchase(plan, source: source) {
            case .purchased:
                purchased = true
                app.haptics.success()
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

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            if try await app.plus.restore() {
                purchased = true
                app.haptics.success()
                dismiss()
            } else {
                message = String(localized: "No Orbi+ purchase was found for this Apple Account.")
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

/// One plan: yearly, monthly or lifetime.
private struct PlanCard: View {
    var plan: PlusPlan
    var savings: Int?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LMSpace.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? LMColor.reward : LMColor.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: LMSpace.xs) {
                        Text(title).font(LMFont.headline).foregroundStyle(LMColor.textPrimary)
                        if let savings {
                            Text("Save \(savings)%")
                                .font(LMFont.eyebrow)
                                .foregroundStyle(LMColor.onAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(LMColor.rewardFill))
                        }
                    }
                    Text(subtitle).font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                }
                Spacer(minLength: 0)
                Text(plan.price)
                    .font(LMFont.headline)
                    .foregroundStyle(LMColor.textPrimary)
            }
            .padding(LMSpace.m)
            .frame(minHeight: 72)
            .glassCard(radius: 22, border: isSelected ? LMColor.rewardFill.opacity(0.8) : nil)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("plus.plan.\(plan.kind.rawValue)")
    }

    private var title: String {
        switch plan.kind {
        case .yearly: String(localized: "Yearly")
        case .monthly: String(localized: "Monthly")
        case .lifetime: String(localized: "Lifetime")
        }
    }

    private var subtitle: String {
        switch plan.kind {
        case .yearly: plan.trialDays.map { String(localized: "\($0) days free, then billed yearly") } ?? String(localized: "Billed yearly")
        case .monthly: plan.trialDays.map { String(localized: "\($0) days free, then billed monthly") } ?? String(localized: "Billed monthly")
        case .lifetime: String(localized: "Pay once, keep it forever")
        }
    }
}

/// A four-pointed star in a soft golden halo: the Orbi+ mark.
struct PlusGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [LMColor.rewardFill.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 48))
            Image(systemName: "sparkle")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(LinearGradient(colors: [Color(hex: Palette.softWhite), LMColor.rewardFill],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: LMColor.rewardFill.opacity(0.8), radius: 14)
        }
    }
}

/// The small "Orbi+" tag on locked things.
struct PlusBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .bold))
            Text(verbatim: "Orbi+").font(LMFont.eyebrow)
        }
        .foregroundStyle(LMColor.onAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(LMColor.rewardFill))
        .accessibilityLabel(Text(verbatim: "Orbi+"))
    }
}

extension View {
    /// Presents the paywall for a locked feature from wherever it was tapped,
    /// including inside sheets and full-screen covers.
    /// `screen` names where the locked thing was, for analytics.
    func plusPaywall(_ feature: Binding<PlusFeature?>, screen: String) -> some View {
        onChange(of: feature.wrappedValue) { _, tapped in
            if let tapped { Telemetry.log(.lockedFeatureTapped(feature: tapped.rawValue, screen: screen)) }
        }
        .sheet(item: feature) { item in
            PlusPaywallView(feature: item, source: "locked_feature")
                .presentationCornerRadius(32)
        }
    }
}
