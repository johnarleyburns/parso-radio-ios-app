import SwiftUI

struct SearchTabView: View {
    @State private var query = ""
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            SearchView()
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.large)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Internet Archive")
    }
}
