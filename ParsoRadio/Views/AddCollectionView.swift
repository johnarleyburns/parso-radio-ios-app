import SwiftUI

struct AddCollectionView: View {
    @ObservedObject private var store = IACollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var collectionId = ""
    @State private var collectionTitle = ""
    @State private var listURL = ""
    @State private var searchQuery = ""
    @State private var searchResults: [IASearchResult] = []
    @State private var isSearching = false
    @State private var mode: Mode = .search
    @State private var pendingResult: IASearchResult?
    @State private var showConfirmAdd = false
    @State private var showAlreadyAdded = false
    @State private var showInvalidURL = false

    enum Mode: String, CaseIterable {
        case search = "Search"
        case manual = "Collection ID"
        case listURL = "List URL"
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Add by", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch mode {
                case .search: searchSection
                case .manual: manualSection
                case .listURL: listURLSection
                }
            }
            .navigationTitle("Add Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Already Added", isPresented: $showAlreadyAdded) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This collection is already in your list.")
            }
            .alert("Add to Collections?", isPresented: $showConfirmAdd) {
                Button("Cancel", role: .cancel) { pendingResult = nil }
                Button("Add") {
                    if let result = pendingResult {
                        let c = IACollection(
                            id: result.id, title: result.title,
                            category: "user", curator: result.creator ?? "",
                            icon: "music.note"
                        )
                        store.addCollection(c)
                        pendingResult = nil
                        dismiss()
                    }
                }
            } message: {
                if let result = pendingResult {
                    Text("\"\(result.title)\"")
                }
            }
            .alert("Invalid URL", isPresented: $showInvalidURL) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enter a valid Internet Archive playlist URL (e.g. https://archive.org/details/@username/lists/N/name).")
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            TextField("Search Internet Archive collections\u{2026}", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { Task { await search() } }
        }

        if isSearching {
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } else if !searchResults.isEmpty {
            Section("Results") {
                ForEach(searchResults) { result in
                    Button {
                        if store.collections.contains(where: { $0.id == result.id }) {
                            showAlreadyAdded = true
                        } else {
                            pendingResult = result
                            showConfirmAdd = true
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if let creator = result.creator {
                                Text(creator)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let count = result.itemCount {
                                Text("\(count) items")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField("Collection ID (e.g. georgeblood)", text: $collectionId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Display name (optional)", text: $collectionTitle)
        } footer: {
            Text("Enter an Internet Archive collection identifier. Find collections at archive.org.")
        }
        Section {
            Button("Add Collection") {
                let id = collectionId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return }
                let title = collectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                store.addCollection(id: id, title: title.isEmpty ? id : title)
                dismiss()
            }
            .disabled(collectionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var listURLSection: some View {
        Section {
            TextField("Playlist URL", text: $listURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
        } footer: {
            Text("Paste a public Internet Archive playlist URL, e.g. https://archive.org/details/@username/lists/N/playlist-name")
        }

        if let info = InternetArchiveService.parseListURL(listURL) {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.displayName)
                            .font(.subheadline.weight(.medium))
                        Text("By @\(info.username)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }

        Section {
            Button("Add Playlist") {
                guard let info = InternetArchiveService.parseListURL(listURL) else {
                    showInvalidURL = true
                    return
                }
                let displayName = listURL.isEmpty ? info.displayName : info.displayName
                let lid = InternetArchiveService.listId(from: listURL) ?? "ia-list-\(info.username)-\(info.listId)"
                let query = InternetArchiveService.listQuery(from: info)

                guard !store.collections.contains(where: { $0.id == lid }) else {
                    showAlreadyAdded = true
                    return
                }
                store.addCollection(id: lid, title: displayName, listURL: info.url, query: query)
                dismiss()
            }
            .disabled(listURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func search() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let urlStr = "https://archive.org/advancedsearch.php?q=mediatype%3Acollection+AND+\(encoded)&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=item_count&rows=20&output=json"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(IACollectionSearchResponse.self, from: data)
            searchResults = response.response.docs
        } catch {
            searchResults = []
        }
    }
}

private struct IACollectionSearchResponse: Decodable {
    struct Response: Decodable { let docs: [IASearchResult] }
    let response: Response
}

private struct IASearchResult: Decodable, Identifiable {
    let id: String
    let title: String
    let creator: String?
    let itemCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "identifier"
        case title
        case creator
        case itemCount = "item_count"
    }
}
