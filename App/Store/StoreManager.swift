import Foundation
import AppKit
import StoreKit
import Combine
import WattsonCore

/// Anything that can answer "does this user have Pro?".
/// The rest of the app depends on this protocol, never on StoreKit directly, which
/// keeps StoreKit out of the views and makes the gating trivially testable.
@MainActor
protocol EntitlementProviding: AnyObject {
    var isPro: Bool { get }
}

/// StoreKit 2 subscription handling.
///
/// There is no account system and no server. Entitlement comes from
/// `Transaction.currentEntitlements`, which Apple already scopes to the signed-in
/// Apple Account and to Family Sharing. That removes the entire class of auth bugs
/// and means the app collects nothing about the user.
@MainActor
final class StoreManager: ObservableObject, EntitlementProviding {

    enum ProductID {
        static let monthly = "com.navwireless.wattson.pro.monthly"
        static let yearly = "com.navwireless.wattson.pro.yearly"
        static let lifetime = "com.navwireless.wattson.pro.lifetime"
        static let all: [String] = [monthly, yearly, lifetime]
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum PurchaseState: Equatable {
        case idle
        case purchasing(productID: String)
        case success
        case cancelled
        /// Ask-to-buy and other deferred approvals.
        case pending
        case failed(String)
    }

    @Published private(set) var products: [Product] = []
    /// The App Store's answer, and the only thing a release build ever consults.
    @Published private(set) var hasVerifiedEntitlement = false
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var activeProductID: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isInGracePeriod = false
    @Published private(set) var isEligibleForIntroductoryOffer = false

    private var updatesTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    /// Overrides the entitlement for local development and for exercising gated UI.
    /// Compiled out of release builds entirely, so there is no code path in a shipped
    /// build that grants Pro without a verified transaction.
    #if DEBUG
    @Published var debugForcePro = false
    var isPro: Bool { hasVerifiedEntitlement || debugForcePro }
    #else
    var isPro: Bool { hasVerifiedEntitlement }
    #endif

    init() {
        listenForTransactions()
    }

    deinit {
        updatesTask?.cancel()
        statusTask?.cancel()
    }

    // MARK: - Loading

    func bootstrap() async {
        await loadProducts()
        await refreshEntitlements()
        await refreshIntroductoryEligibility()
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: ProductID.all)
            // Cheapest-first within subscriptions, lifetime last: the order the
            // paywall reads best in.
            products = fetched.sorted { lhs, rhs in
                if lhs.type == rhs.type { return lhs.price < rhs.price }
                return lhs.type == .autoRenewable && rhs.type != .autoRenewable
            }
            loadState = products.isEmpty ? .failed("No products were returned by the App Store.") : .loaded
        } catch {
            Log.store.error("Product load failed: \(error.localizedDescription, privacy: .public)")
            loadState = .failed("Could not reach the App Store. Wattson keeps working — try again later.")
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async {
        purchaseState = .purchasing(productID: product.id)
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verified(verification) else {
                    purchaseState = .failed("That purchase could not be verified by the App Store.")
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                purchaseState = .success

            case .userCancelled:
                purchaseState = .cancelled

            case .pending:
                // Ask to Buy, or a payment method needing approval.
                purchaseState = .pending

            @unknown default:
                purchaseState = .failed("The App Store returned an unexpected result.")
            }
        } catch {
            Log.store.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            purchaseState = .failed(StoreManager.humanReadable(error))
        }
    }

    /// "Restore Purchases" — required by App Review for any app with non-consumables.
    func restore() async {
        purchaseState = .purchasing(productID: "restore")
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            purchaseState = isPro
                ? .success
                : .failed("No previous purchase was found on this Apple Account.")
        } catch {
            Log.store.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            purchaseState = .failed(StoreManager.humanReadable(error))
        }
    }

    func resetPurchaseState() {
        purchaseState = .idle
    }

    /// Opens the system subscription management sheet.
    func showManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var entitled = false
        var newestProductID: String?
        var newestExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result) else { continue }
            guard ProductID.all.contains(transaction.productID) else { continue }
            // A refunded or revoked transaction grants nothing.
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry <= Date() { continue }

            entitled = true
            if newestExpiry == nil || (transaction.expirationDate ?? .distantFuture) > (newestExpiry ?? .distantPast) {
                newestExpiry = transaction.expirationDate
                newestProductID = transaction.productID
            }
        }

        hasVerifiedEntitlement = entitled
        activeProductID = newestProductID
        expirationDate = newestExpiry
        await refreshSubscriptionStatus()

        Log.store.info("Entitlement refreshed: pro=\(entitled, privacy: .public)")
    }

    private func refreshSubscriptionStatus() async {
        isInGracePeriod = false
        guard
            let subscription = products.first(where: { $0.id == activeProductID })?.subscription,
            let statuses = try? await subscription.status
        else { return }

        for status in statuses {
            switch status.state {
            case .inGracePeriod:
                // Billing retry: keep Pro switched on. Failing to renew a card is
                // not a reason to take features away mid-cycle.
                isInGracePeriod = true
                hasVerifiedEntitlement = true
            case .subscribed:
                hasVerifiedEntitlement = true
            default:
                continue
            }
        }
    }

    private func refreshIntroductoryEligibility() async {
        guard let subscription = products.first(where: { $0.subscription != nil })?.subscription else {
            isEligibleForIntroductoryOffer = false
            return
        }
        isEligibleForIntroductoryOffer = await subscription.isEligibleForIntroOffer
    }

    /// A transaction that fails verification is treated as if it does not exist.
    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            Log.store.error("Unverified transaction rejected: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Renewals, refunds, family sharing changes and purchases made on another
    /// device all arrive here.
    private func listenForTransactions() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = await self.verified(update) {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    // MARK: - Presentation helpers

    static func humanReadable(_ error: Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return "The App Store could not be reached. Check your connection and try again."
            case .userCancelled:
                return "Purchase cancelled."
            case .notAvailableInStorefront:
                return "Wattson Pro is not available in your region's App Store yet."
            case .notEntitled:
                return "This Apple Account is not entitled to that purchase."
            default:
                return "The App Store reported a problem. Please try again."
            }
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return "That subscription is temporarily unavailable."
            case .purchaseNotAllowed:
                return "Purchases are not allowed on this Mac. Check Screen Time restrictions."
            case .ineligibleForOffer:
                return "This Apple Account is not eligible for that offer."
            default:
                return "The purchase could not be completed."
            }
        }
        return error.localizedDescription
    }

    func displayPrice(for product: Product) -> String {
        product.displayPrice
    }

    /// "£2.49 / month", "£19.99 / year", "£39.99 once".
    func priceCadence(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "once" }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "\(period.value) days"
        case .week: unit = period.value == 1 ? "week" : "\(period.value) weeks"
        case .month: unit = period.value == 1 ? "month" : "\(period.value) months"
        case .year: unit = period.value == 1 ? "year" : "\(period.value) years"
        @unknown default: unit = "period"
        }
        return unit
    }

    /// "7 days free, then …" when the account is eligible.
    func introductoryOfferText(for product: Product) -> String? {
        guard
            isEligibleForIntroductoryOffer,
            let offer = product.subscription?.introductoryOffer
        else { return nil }

        let count = offer.period.value
        let unitName: String
        switch offer.period.unit {
        case .day: unitName = count == 1 ? "day" : "days"
        case .week: unitName = count == 1 ? "week" : "weeks"
        case .month: unitName = count == 1 ? "month" : "months"
        case .year: unitName = count == 1 ? "year" : "years"
        @unknown default: unitName = "period"
        }

        switch offer.paymentMode {
        case .freeTrial:
            return "\(count) \(unitName) free, then \(product.displayPrice)"
        case .payAsYouGo:
            return "\(offer.displayPrice) per \(unitName) for \(count) \(unitName)"
        case .payUpFront:
            return "\(offer.displayPrice) for the first \(count) \(unitName)"
        default:
            return nil
        }
    }

    /// Savings badge for the yearly plan, computed from the real prices rather than
    /// hard-coded, so a price change in App Store Connect cannot make it lie.
    func annualSavingPercent() -> Int? {
        guard
            let monthly = products.first(where: { $0.id == ProductID.monthly }),
            let yearly = products.first(where: { $0.id == ProductID.yearly })
        else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0 else { return nil }
        let saving = (twelveMonths - yearly.price) / twelveMonths * 100
        let rounded = Int((saving as NSDecimalNumber).doubleValue.rounded())
        return rounded > 0 ? rounded : nil
    }
}