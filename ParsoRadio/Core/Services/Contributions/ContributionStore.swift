import Foundation
import StoreKit

/// StoreKit 2 layer for one-time contribution tips (consumables).
/// Dormant until the product IDs below are configured in App
/// Store Connect (no products → the Support UI simply shows nothing to buy).
///
/// Not unit-tested here — StoreKit can't run in the Linux test image; the
/// testable decision logic lives in ContributionPromptEngine. This shell is the
/// mechanism (validated on CI + device, like the audio resource loader).
@MainActor
final class ContributionStore: ObservableObject {
    static let productIDs = [
        "guru.parso.tip.small",       // $1.99
        "guru.parso.tip.medium",      // $4.99
        "guru.parso.tip.generous",    // $9.99
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var everContributed =
        UserDefaults.standard.bool(forKey: "parso.everContributed")
    @Published private(set) var purchasingID: String?
    @Published var lastError: String?

    var isSupporter: Bool { everContributed }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let all = try await Product.products(for: Self.productIDs)
            products = all.sorted { $0.price < $1.price }
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
        for await result in Transaction.currentEntitlements {
            guard case .verified = result else { continue }
            markContributed()
        }
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
                await self?.markContributed()
                await transaction.finish()
            }
        }
    }
}
