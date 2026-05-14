import SwiftUI

struct SearchView: View {
    @EnvironmentObject var playlistVM: PlaylistViewModel
    @StateObject private var searchVM: SearchViewModel
    @State private var showAddToPlaylist: Track? = nil
    @Environment(\.dismiss) private var dismiss

    init(archiveService: InternetArchiveService = InternetArchiveService()) {
        _searchVM = StateObject(wrappedValue: SearchViewModel(
            archiveService: archiveService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $searchVM.source) {
                    ForEach(SearchViewModel.SearchSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if searchVM.isSearching {
                    ProgressView()
                        .padding()
                }

                if let error = searchVM.errorMessage {
                    Text(error)
                        .foregroundStyle(.secondary)
                        .padding()
                }

                List {
                    ForEach(Array(searchVM.results.enumerated()), id: \.element.id) { index, group in
                        Section {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.title)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(group.creator)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let date = group.addedDate {
                                        Text(date.formatted(.dateTime.year().month().day()))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                Text("\(group.trackCount) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button {
                                    Task { await searchVM.expandGroup(at: index) }
                                } label: {
                                    Image(systemName: group.isExpanded ? "chevron.up" : "chevron.down")
                                }
                            }

                            if group.isExpanded {
                                ForEach(group.tracks) { track in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title).font(.subheadline).lineLimit(1)
                                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(Duration.seconds(track.duration)
                                            .formatted(.time(pattern: .minuteSecond)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button {
                                            showAddToPlaylist = track
                                        } label: {
                                            Image(systemName: "plus.circle")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if searchVM.hasMorePages {
                        ProgressView()
                            .task { await searchVM.loadNextPage() }
                    }
                }
            }
            .searchable(text: $searchVM.query, prompt: "Search music, audiobooks…")
            .onChange(of: searchVM.query) { _ in searchVM.searchChanged() }
            .onChange(of: searchVM.source) { _ in searchVM.searchChanged() }
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
        }
    }
}
