import SwiftUI

struct AddCollectionView: View {
    @ObservedObject private var store = IACollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var collectionId = ""
    @State private var collectionTitle = ""
    @State private var searchQuery = ""
    @State private var searchResults: [IASearchResult] = []
    @State private var isSearching = false
    @State private var mode: Mode = .manual

    enum Mode: String, CaseIterable {
        case manual = "Collection ID"
        case search = "Search"
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

                if mode == .manual {
                    manualSection
                } else {
                    searchSection
                }
            }
            .navigationTitle("Add Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
    private var searchSection: some View {
        Section {
            TextField("Search Internet Archive collections…", text: $searchQuery)
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
                        let c = IACollection(
                            id: result.id, title: result.title,
                            category: "user", curator: result.creator ?? "",
                            icon: "music.note", isDefault: false
                        )
                        store.addCollection(c)
                        dismiss()
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
                    .disabled(store.collections.contains { $0.id == result.id })
                }
            }
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
