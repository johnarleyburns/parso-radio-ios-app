import SwiftUI
import StoreKit

/// One-time contribution tips. If the user has ever contributed, the view
/// shows a thank-you message and invites another tip. If no products load
/// (ASC not configured yet) it shows a gentle placeholder.
struct ContributionSupportView: View {
    @ObservedObject var store: ContributionStore
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = false

    var body: some View {
        List {
            Section {
                if store.isSupporter {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Thank you for your support!", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                            .font(.headline)
                        Text("Lorewave stays free and ad-free because of listeners like you. Want to buy us another coffee?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Lorewave is free and ad-free. A contribution helps cover hosting, copyright/DMCA handling, and development — and we give 10% of our proceeds (after Apple's commission) to the Internet Archive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !store.products.isEmpty {
                Section("Tips") {
                    ForEach(store.products, id: \.id) { purchaseRow($0) }
                }
            }

            if store.products.isEmpty {
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
        .accessibilityLabel("Purchase \(product.displayName) for \(product.displayPrice)")
        .accessibilityHint(product.description)
    }
}
