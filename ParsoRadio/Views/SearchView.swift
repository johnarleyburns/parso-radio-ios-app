import SwiftUI

struct SearchView: View {
    var dismissAll: (() -> Void)? = nil
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @StateObject private var searchVM: SearchViewModel
    @State private var showAddToPlaylist: Track? = nil
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(dismissAll: (() -> Void)? = nil,
         archiveService: InternetArchiveService = InternetArchiveService()) {
        self.dismissAll = dismissAll
        _searchVM = StateObject(wrappedValue: SearchViewModel(
            archiveService: archiveService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search music, audiobooks…", text: $searchVM.query)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onChange(of: searchVM.query) { _ in searchVM.searchChanged() }
                    if !searchVM.query.isEmpty {
                        Button { searchVM.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                if searchVM.isSearching {
                    ProgressView().padding()
                }
                if let error = searchVM.errorMessage {
                    ContentUnavailableView("Search failed", systemImage: "wifi.slash",
                                            description: Text(error))
                } else if searchVM.showNoResults {
                    ContentUnavailableView.search(text: searchVM.query)
                }

                List {
                    ForEach(searchVM.results) { group in
                        let dur = searchVM.durations[group.id] ?? group.duration
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.body).fontWeight(.medium).lineLimit(2)
                                Text(group.creator)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let date = group.addedDate {
                                    Text(date.formatted(.dateTime.year().month().day()))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if dur > 0 {
                                Text(Duration.seconds(dur)
                                    .formatted(.time(pattern: .hourMinuteSecond)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                showAddToPlaylist = searchTrack(group)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await playerVM.playSearchResult(group)
                                dismissAll?()
                            }
                        }
                        .task { searchVM.loadDuration(group.id) }
                    }

                    if searchVM.hasMorePages {
                        ProgressView()
                            .task { await searchVM.loadNextPage() }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $showAddToPlaylist) { track in
                AddToPlaylistSheet(track: track)
                    .environmentObject(playlistVM)
            }
            .onAppear { searchFocused = true }   // cursor ready immediately
        }
    }

    private func searchTrack(_ group: SearchViewModel.ResultGroup) -> Track {
        Track(
            id: group.id, source: "internet_archive",
            title: group.title, artist: group.creator,
            duration: group.duration,
            streamURL: URL(string: "https://archive.org/download/\(group.id)")
                ?? URL(string: "https://archive.org")!,
            downloadURL: nil, localFilePath: nil,
            license: .publicDomain, tags: [],
            qualityScore: 1.0, rawCreator: group.creator,
            composer: nil, instruments: [],
            metadataConfidence: 0.0, addedDate: group.addedDate
        )
    }
}
