import SwiftUI
import StoreKit

/// The purchase UI — used both as the toast's "Support" sheet and the
/// Settings → Support section. Shows the one-time tips, the monthly/yearly
/// subscription, Restore, Manage Subscription, and the required disclosures.
/// If no products load (ASC not configured yet) it shows a gentle placeholder.
struct ContributionSupportView: View {
    @ObservedObject var store: ContributionStore
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = false

    var body: some View {
        List {
            Section {
                Text("Lorewave is free and ad-free. A contribution helps cover hosting, copyright/DMCA handling, and development — and we give 10% of our proceeds (after Apple's commission) to the Internet Archive.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if store.isSupporter {
                    Label("You're a supporter — thank you!", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
            }

            if !store.oneTimeProducts.isEmpty {
                Section("One-time") {
                    ForEach(store.oneTimeProducts, id: \.id) { purchaseRow($0) }
                }
            }

            if !store.subscriptionProducts.isEmpty {
                Section {
                    ForEach(store.subscriptionProducts, id: \.id) { purchaseRow($0) }
                    if store.hasActiveSubscription {
                        Button("Manage Subscription") {
                            Task { await store.showManageSubscriptions() }
                        }
                    }
                } header: {
                    Text("Monthly / Yearly")
                } footer: {
                    Text("Supporters get exclusive app icons and help shape the roadmap. Subscriptions renew automatically until cancelled in Settings.")
                }
            }

            if store.oneTimeProducts.isEmpty && store.subscriptionProducts.isEmpty {
                Section {
                    Text("Support options aren't available yet. Please check back soon.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Purchases") { Task { await store.restore() } }
            } footer: {
                Text("By contributing you agree to the Terms of Use and Privacy Policy (see About).")
            }
        }
        .navigationTitle("Support Lorewave")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func purchaseRow(_ product: Product) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.body).foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice).fontWeight(.semibold)
                }
            }
        }
        .disabled(store.purchasingID != nil)
    }
}
