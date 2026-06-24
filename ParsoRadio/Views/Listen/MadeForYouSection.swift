import SwiftUI

struct MadeForYouSection: View {
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var shelfStore: MadeForYouShelfStore = {
        let store = MadeForYouShelfStore(
            db: DatabaseService.shared,
            tasteProfileStore: TasteProfileStore(db: DatabaseService.shared)
        )
        return store
    }()

    var body: some View {
        Section {
            switch shelfStore.state {
            case .idle:
                Color.clear
                    .frame(height: 0)
                    .listRowBackground(Color.clear)

            case .loading:
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Finding fresh picks...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 120)
                .listRowBackground(Color.clear)

            case .loaded(_, let tracks) where !tracks.isEmpty:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(tracks, id: \.id) { track in
                            Button {
                                Task { await playerVM.playRecentTrack(track) }
                            } label: {
                                JumpBackInCard(track: track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)

            case .loaded(_, let tracks):
                Text("No picks available right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
                    .listRowBackground(Color.clear)

            case .empty(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await shelfStore.loadIfNeeded() }
                    }
                    .font(.caption)
                }
                .frame(height: 80)
                .listRowBackground(Color.clear)

            case .failed(let message, let retryable):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if retryable {
                        Button("Retry") {
                            Task { await shelfStore.loadIfNeeded() }
                        }
                        .font(.caption)
                    }
                }
                .frame(height: 80)
                .listRowBackground(Color.clear)
            }
        } header: {
            if case .loaded(let kind, let tracks) = shelfStore.state, !tracks.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                                                             Color(red: 0.10, green: 0.22, blue: 0.65)]),
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    Text("Made for You")
                        .font(.headline.weight(.semibold))
                }
            }
        } footer: {
            if case .loaded(let kind, let tracks) = shelfStore.state, !tracks.isEmpty {
                switch kind {
                case .personalized:
                    Text("Fresh picks from your taste \u{00B7} refreshes daily")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .coldStart:
                    Text("Starter picks while Lorewave learns \u{00B7} refreshes daily")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: playerVM.playHistoryVersion) {
            shelfStore.setArchiveService(deps.archiveService)
            await shelfStore.loadIfNeeded()
        }
    }
}
