import SwiftUI

struct ChannelSelectorView: View {
    let currentChannelId: String
    let onSelect: (Channel) -> Void

    @Environment(\.dismiss) private var dismiss

    // UC6: favorites populated automatically from UserDefaults (MRU order).
    @State private var favoriteIds: [String] =
        UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []

    private var sortedCategories: [String] {
        Channel.categories.sorted()
    }

    private var favoriteChannels: [Channel] {
        favoriteIds.compactMap { id in Channel.defaults.first { $0.id == id } }
    }

    private func channels(for category: String) -> [Channel] {
        Channel.defaults
            .filter { $0.category == category }
            .sorted { $0.name < $1.name }
    }

    private func removeFavorite(_ channel: Channel) {
        favoriteIds.removeAll { $0 == channel.id }
        var stored = UserDefaults.standard.stringArray(forKey: "visitedChannelIds") ?? []
        stored.removeAll { $0 == channel.id }
        UserDefaults.standard.set(stored, forKey: "visitedChannelIds")
    }

    var body: some View {
        NavigationStack {
            List {
                if !favoriteChannels.isEmpty {
                    Section("Favorites") {
                        ForEach(favoriteChannels) { channel in
                            Button { onSelect(channel) } label: { channelRow(channel) }
                                .buttonStyle(.plain)
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
                            Button { onSelect(channel) } label: { channelRow(channel) }
                                .buttonStyle(.plain)
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
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(categoryGradient(for: channel.category))
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
    }
}

#Preview {
    ChannelSelectorView(currentChannelId: "bach-vivaldi-strings") { _ in }
}
