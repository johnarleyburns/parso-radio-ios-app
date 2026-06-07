import SwiftUI

enum PodcastAddMode { case url, search }

struct PodcastAddView: View {
    let initialMode: PodcastAddMode

    @Environment(\.dismiss) private var dismiss

    @State private var feedURL = ""
    @State private var searchQuery = ""
    @State private var searchResults: [PodcastSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var subscribeName = ""
    @State private var discoveredArtworkURL: String?

    @StateObject private var store = PodcastSubscriptionStore.shared
    @FocusState private var focusURL: Bool

    var body: some View {
        NavigationStack {
            Form {
                // Manual URL entry
                Section {
                    TextField("https://feeds.example.com/podcast.xml", text: $feedURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusURL)
                    Button {
                        Task { await fetchFromURL() }
                    } label: {
                        if isLoading {
                            HStack { ProgressView(); Text("Fetching feed…") }
                        } else {
                            Label("Fetch & Preview", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(feedURL.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                } header: {
                    Text("Add by URL")
                } footer: {
                    Text("Paste the RSS feed URL of any public podcast. The feed will be parsed to confirm it contains audio episodes.")
                }

                if !subscribeName.isEmpty {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(subscribeName).font(.headline)
                                Text(feedURL).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Subscribe") {
                                Task {
                                    await store.add(name: subscribeName, feedURL: feedURL,
                                                    artworkURL: discoveredArtworkURL)
                                    dismiss()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                // Search
                Section {
                    TextField("Search iTunes Podcasts…", text: $searchQuery)
                        .onSubmit { Task { await search() } }
                } header: {
                    Text("Or Search")
                }

                if !searchResults.isEmpty {
                    Section("Results") {
                        ForEach(searchResults) { result in
                            Button {
                                feedURL = result.feedURL
                                subscribeName = result.title
                                discoveredArtworkURL = result.artworkURL
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).font(.body).foregroundStyle(.primary)
                                    Text(result.artist).font(.caption).foregroundStyle(.secondary)
                                    Text("\(result.trackCount) episodes")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear {
                if initialMode == .url { focusURL = true }
            }
        }
    }

    private func fetchFromURL() async {
        guard let url = URL(string: feedURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" else {
            errorMessage = "Please enter a valid HTTPS feed URL."
            showError = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let channel = Channel(
                id: "preview", name: "Preview",
                category: "Podcasts", icon: "antenna.radiowaves.left.and.right",
                tags: ["preview"],
                contentType: .spokenWord, preferredSource: "podcast",
                feedURL: feedURL
            )
            let service = PodcastRSSService()
            let tracks = try await service.fetchTracks(channel: channel)
            if tracks.isEmpty {
                errorMessage = "This feed contains no playable audio episodes."
                showError = true
            } else {
                let title = tracks.first(where: { $0.artist != "Podcasts" })?.artist
                    ?? tracks.first?.title
                    ?? URL(string: feedURL)?.host
                    ?? "Podcast"
                subscribeName = title
            }
        } catch {
            errorMessage = "Could not fetch feed: \(error.localizedDescription)"
            showError = true
        }
    }

    private func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            searchResults = try await PodcastSearchService.shared.search(term: q)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
