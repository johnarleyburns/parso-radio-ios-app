import SwiftUI

struct ChannelSelectorView: View {
    let currentChannelId: String
    let onSelect: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss

    // Explicit favorites — only added via the heart button, never auto-populated.
    @State private var favoriteIds: [String] =
        UserDefaults.standard.stringArray(forKey: "favoriteChannelIds") ?? []

    // Curated appears first after Favorites; remaining categories in a fixed preferred order.
    private var sortedCategories: [String] {
        let preferred = ["Curated", "Ambient", "Audiobooks", "Lectures", "Podcasts"]
        let available = Set(Channel.categories)
        let extra = Channel.categories.filter { !preferred.contains($0) }.sorted()
        return preferred.filter { available.contains($0) } + extra
    }

    private var favoriteChannels: [Channel] {
        favoriteIds.compactMap { id in Channel.defaults.first { $0.id == id } }
    }

    private func channels(for category: String) -> [Channel] {
        Channel.defaults
            .filter { $0.category == category }
            .sorted { $0.name < $1.name }
    }

    private func isFavorite(_ channel: Channel) -> Bool {
        favoriteIds.contains(channel.id)
    }

    private func toggleFavorite(_ channel: Channel) {
        if let idx = favoriteIds.firstIndex(of: channel.id) {
            favoriteIds.remove(at: idx)
        } else {
            favoriteIds.insert(channel.id, at: 0)
        }
        UserDefaults.standard.set(favoriteIds, forKey: "favoriteChannelIds")
    }

    private func removeFavorite(_ channel: Channel) {
        favoriteIds.removeAll { $0 == channel.id }
        UserDefaults.standard.set(favoriteIds, forKey: "favoriteChannelIds")
    }

    var body: some View {
        NavigationStack {
            List {
                if !favoriteChannels.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteChannels) { channel in
                            channelRow(channel)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        removeFavorite(channel)
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                }
                        }
                    }
                }

                ForEach(sortedCategories, id: \.self) { category in
                    Section(category) {
                        ForEach(channels(for: category)) { channel in
                            channelRow(channel)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: Channel) -> some View {
        HStack(spacing: 14) {
            Button {
                onSelect(channel)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ChannelCategoryStyle.gradient(for: channel.category))
                            .frame(width: 36, height: 36)
                        Image(systemName: channel.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    Text(channel.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    if channel.id == currentChannelId {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(channel)
            } label: {
                Image(systemName: isFavorite(channel) ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorite(channel) ? Color.red : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    ChannelSelectorView(currentChannelId: "guitar-classical") { _ in }
}
