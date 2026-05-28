import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// StoreKit 2 layer for the contribution feature (CONTRIBUTIONS-PROPOSAL.md).
/// One-time tips are CONSUMABLES; monthly/yearly support are AUTO-RENEWABLE
/// subscriptions. Dormant until the product IDs below are configured in App
/// Store Connect (no products → the Support UI simply shows nothing to buy).
///
/// Not unit-tested here — StoreKit can't run in the Linux test image; the
/// testable decision logic lives in ContributionPromptEngine. This shell is the
/// mechanism (validated on CI + device, like the audio resource loader).
@MainActor
final class ContributionStore: ObservableObject {
    // Configure these EXACT identifiers in App Store Connect.
    static let oneTimeIDs = [
        "guru.parso.tip.small",       // $1.99
        "guru.parso.tip.medium",      // $4.99
        "guru.parso.tip.generous",    // $9.99
    ]
    static let subscriptionIDs = [
        "guru.parso.support.monthly", // $2.99/mo
        "guru.parso.support.yearly",  // $24.99/yr
    ]
    static var allIDs: [String] { oneTimeIDs + subscriptionIDs }

    @Published private(set) var oneTimeProducts: [Product] = []
    @Published private(set) var subscriptionProducts: [Product] = []
    @Published private(set) var hasActiveSubscription = false
    /// One-time tips don't persist as StoreKit entitlements, so we remember that
    /// the user has ever contributed (unlocks the cosmetic perks / "Supporter").
    @Published private(set) var everContributed =
        UserDefaults.standard.bool(forKey: "parso.everContributed")
    @Published private(set) var purchasingID: String?
    @Published var lastError: String?

    /// Supporter = ever tipped OR has an active support subscription.
    var isSupporter: Bool { everContributed || hasActiveSubscription }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task { await loadProducts(); await refreshSubscriptionStatus() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.allIDs)
            oneTimeProducts = products
                .filter { Self.oneTimeIDs.contains($0.id) }
                .sorted { $0.price < $1.price }
            subscriptionProducts = products
                .filter { Self.subscriptionIDs.contains($0.id) }
                .sorted { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Couldn't verify the purchase."
                    return false
                }
                markContributed()
                if transaction.productType == .autoRenewable { hasActiveSubscription = true }
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshSubscriptionStatus()
    }

    /// Re-derive subscription status from the current entitlements.
    func refreshSubscriptionStatus() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result else { continue }
            if Self.subscriptionIDs.contains(t.productID), t.revocationDate == nil {
                active = true
                markContributed()
            }
        }
        hasActiveSubscription = active
    }

    /// Opens Apple's manage-subscriptions sheet — you can't cancel a sub in-app.
    func showManageSubscriptions() async {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        #endif
    }

    private func markContributed() {
        if !everContributed {
            everContributed = true
            UserDefaults.standard.set(true, forKey: "parso.everContributed")
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.apply(transaction)
            }
        }
    }

    private func apply(_ transaction: Transaction) async {
        markContributed()
        await refreshSubscriptionStatus()
        await transaction.finish()
    }
}
