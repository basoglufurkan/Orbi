import Foundation
import Observation
import os
import RevenueCat
import StoreKit

/// One way to buy Orbi+, as the paywall shows it.
struct PlusPlan: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Sendable { case yearly, monthly, lifetime }

    var kind: Kind
    var price: String
    var priceValue: Decimal
    /// A free trial the store will give this person, in days.
    var trialDays: Int?
    var productID: String
    /// ISO 4217, for revenue reports.
    var currency: String
    /// RevenueCat's package; nil for the DEBUG sample plans.
    fileprivate var package: Package?

    var id: String { kind.rawValue }

    static func == (a: PlusPlan, b: PlusPlan) -> Bool {
        a.kind == b.kind && a.price == b.price && a.trialDays == b.trialDays
    }
}

/// Orbi+ through RevenueCat: what's for sale, buying, restoring, and
/// whether the `plus` entitlement is active. The answer is mirrored into
/// `PlusAccess` so it holds offline and at launch, before the store replies.
@MainActor
@Observable
final class PlusStore {
    enum Availability: Equatable { case loading, ready, unavailable }

    /// The public SDK key from RevenueCat › Project settings › API keys. It isn't in the
    /// source: `REVENUECAT_API_KEY` in `Config/Secrets.xcconfig` (not in the repository; see
    /// `Config/Secrets.example.xcconfig`) reaches the Info.plist as `RevenueCatAPIKey`.
    /// DEBUG builds take the Test Store key (`test_`), which sells RevenueCat's test products
    /// without App Store Connect; release builds need the App Store key (`appl_`). Without a
    /// key the store stays off.
    static let apiKey: String = {
        let key = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// The same identifiers as App Store Connect and RevenueCat.
    enum Product {
        static let monthly = "com.mobapptech.lumora.plus.monthly"
        static let yearly = "com.mobapptech.lumora.plus.yearly"
        static let lifetime = "com.mobapptech.lumora.plus.lifetime"
    }

    private(set) var isActive: Bool
    private(set) var plans: [PlusPlan] = []
    private(set) var availability: Availability = .loading
    /// Lifetime purchases never renew; nothing to manage.
    private(set) var isLifetime = false
    private(set) var renewalDate: Date?

    /// Called when Orbi+ starts or ends, so things that depend on it redraw.
    @ObservationIgnored var didChange: ((Bool) -> Void)?

    @ObservationIgnored private let override: Bool?
    @ObservationIgnored private let isConfigured: Bool
    @ObservationIgnored private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "Plus")

    init(override: Bool? = nil, enabled: Bool = true) {
        self.override = override
        isActive = override ?? PlusAccess.isActive
        isConfigured = enabled && !Self.apiKey.isEmpty
        if let override { PlusAccess.defaults.set(override, forKey: PlusAccess.key) }
        guard isConfigured else {
            availability = .unavailable
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        // Lets RevenueCat's Firebase integration send renewals, cancellations and refunds,
        // which the app itself never sees.
        if let firebaseID = Telemetry.appInstanceID {
            Purchases.shared.attribution.setFirebaseAppInstanceID(firebaseID)
        }
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    // MARK: Plans

    func loadPlans() async {
        guard isConfigured else {
            #if DEBUG
            plans = Self.samplePlans
            #endif
            availability = plans.isEmpty ? .unavailable : .ready
            return
        }
        if plans.isEmpty { availability = .loading }
        do {
            let offerings = try await Purchases.shared.offerings()
            var loaded: [PlusPlan] = []
            for package in offerings.current?.availablePackages ?? [] {
                guard let kind = Self.kind(of: package) else { continue }
                let product = package.storeProduct
                var trial: Int?
                // "Unknown" (common in sandbox and on a fresh install) counts as eligible:
                // StoreKit applies the trial at purchase only if the person really is.
                if let intro = product.introductoryDiscount, intro.paymentMode == .freeTrial,
                   await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: product) != .ineligible {
                    trial = Self.days(in: intro.subscriptionPeriod)
                }
                loaded.append(PlusPlan(kind: kind, price: product.localizedPriceString, priceValue: product.price,
                                       trialDays: trial, productID: product.productIdentifier,
                                       currency: product.currencyCode ?? "USD", package: package))
            }
            plans = PlusPlan.Kind.allCases.compactMap { kind in loaded.first { $0.kind == kind } }
            availability = plans.isEmpty ? .unavailable : .ready
        } catch {
            logger.error("Offerings failed: \(error.localizedDescription)")
            Telemetry.log(.offeringsFailed(error: Self.code(of: error)))
            availability = plans.isEmpty ? .unavailable : .ready
        }
    }

    /// How much the yearly plan saves against twelve monthly payments, in percent.
    var yearlySavings: Int? {
        guard let year = plans.first(where: { $0.kind == .yearly })?.priceValue,
              let month = plans.first(where: { $0.kind == .monthly })?.priceValue, month > 0 else { return nil }
        let saving = 1 - (year as NSDecimalNumber).doubleValue / ((month as NSDecimalNumber).doubleValue * 12)
        let percent = Int((saving * 100).rounded())
        return percent >= 5 ? percent : nil
    }

    // MARK: Buying

    enum PurchaseOutcome: Equatable { case purchased, cancelled, pending }

    /// Buys a plan and reports the whole funnel: begin_checkout, then purchase
    /// (or a trial start), cancellation, pending approval or failure.
    func purchase(_ plan: PlusPlan, source: String) async throws -> PurchaseOutcome {
        let info = TelemetryEvent.PurchaseInfo(plan: plan.kind.rawValue, productID: plan.productID,
                                               price: (plan.priceValue as NSDecimalNumber).doubleValue,
                                               currency: plan.currency, trialDays: plan.trialDays, source: source)
        Telemetry.log(.beginCheckout(info))
        do {
            guard let package = plan.package else { throw PlusError.unavailable }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                Telemetry.log(.purchaseCancelled(plan: info.plan))
                return .cancelled
            }
            apply(result.customerInfo)
            guard isActive else {
                Telemetry.log(.purchasePending(plan: info.plan))
                return .pending
            }
            let trial = plan.trialDays != nil
            if trial {
                Telemetry.log(.trialStarted(info))
            } else {
                Telemetry.log(.purchase(info, transactionID: result.transaction?.transactionIdentifier))
            }
            Telemetry.log(.purchaseCompleted(info, trial: trial))
            return .purchased
        } catch {
            Telemetry.log(.purchaseFailed(plan: info.plan, error: Self.code(of: error)))
            throw error
        }
    }

    /// True if restoring found Orbi+.
    func restore() async throws -> Bool {
        Telemetry.log(.restoreStarted)
        do {
            guard isConfigured else { throw PlusError.unavailable }
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            Telemetry.log(.restoreCompleted(found: isActive))
            return isActive
        } catch {
            Telemetry.log(.restoreFailed(error: Self.code(of: error)))
            throw error
        }
    }

    /// After a reinstall RevenueCat may not know about Orbi+ bought earlier
    /// with this Apple Account. If StoreKit says it's owned, hand it over so
    /// Orbi+ turns on (no sign-in prompt, unlike a restore).
    func syncOwnedPurchases() async {
        guard isConfigured, !isActive else { return }
        let ours: Set<String> = [Product.monthly, Product.yearly, Product.lifetime]
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, ours.contains(transaction.productID) {
                owned = true
                break
            }
        }
        guard owned else { return }
        do { apply(try await Purchases.shared.syncPurchases()) } catch {
            logger.error("Syncing purchases failed: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        guard isConfigured else { return }
        do { apply(try await Purchases.shared.customerInfo()) } catch {
            logger.error("Customer info failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[PlusAccess.entitlement]
        let active = override ?? (entitlement?.isActive == true)
        isLifetime = entitlement?.isActive == true && entitlement?.expirationDate == nil
        renewalDate = entitlement?.willRenew == true ? entitlement?.expirationDate : nil
        guard active != isActive || PlusAccess.isActive != active else { return }
        Telemetry.log(.plusStatusChanged(from: isActive ? "plus" : "free", to: active ? "plus" : "free"))
        isActive = active
        PlusAccess.defaults.set(active, forKey: PlusAccess.key)
        didChange?(active)
    }

    /// A short, stable error label for analytics (no messages, which are localized).
    static func code(of error: Error) -> String {
        if let rc = error as? ErrorCode { return "rc_\(rc.rawValue)" }
        let ns = error as NSError
        return "\(ns.domain)_\(ns.code)"
    }

    private static func kind(of package: Package) -> PlusPlan.Kind? {
        switch package.packageType {
        case .monthly: .monthly
        case .annual: .yearly
        case .lifetime: .lifetime
        default:
            switch package.storeProduct.productIdentifier {
            case Product.monthly: .monthly
            case Product.yearly: .yearly
            case Product.lifetime: .lifetime
            default: nil
            }
        }
    }

    private static func days(in period: RevenueCat.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        }
    }

    #if DEBUG
    /// Shown while no API key is set, so the paywall can be designed and tested.
    private static let samplePlans = [
        PlusPlan(kind: .yearly, price: "₺599,99", priceValue: 599.99, trialDays: 7, productID: Product.yearly, currency: "TRY"),
        PlusPlan(kind: .monthly, price: "₺99,99", priceValue: 99.99, trialDays: nil, productID: Product.monthly, currency: "TRY"),
        PlusPlan(kind: .lifetime, price: "₺1.499,99", priceValue: 1499.99, trialDays: nil, productID: Product.lifetime, currency: "TRY"),
    ]
    #endif
}

enum PlusError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "The App Store isn't reachable right now. Try again in a moment.")
    }
}
