import SwiftUI

/// The ONLY menu reachable while Kids Mode is on: a short list of the children's
/// channels, plus a lock button that requires the parent PIN to exit. No search,
/// no other categories, no Settings.
struct KidsMenuView: View {
    let onSelectChannel: (Channel) -> Void
    @ObservedObject private var kids = KidsModeController.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showExitPin = false
    @State private var pinEntry = ""
    @State private var showWrongPin = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(KidsModeController.allowedChannels(), id: \.id) { ch in
                        Button {
                            onSelectChannel(ch)
                            dismiss()
                        } label: {
                            Label(ch.name, systemImage: ch.icon)
                                .font(.title3)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Listen")
                } footer: {
                    Text("Songs and stories chosen for kids.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lorewave Kids")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pinEntry = ""
                        showExitPin = true
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel("Exit Kids Mode")
                }
            }
            .alert("Enter PIN to exit Kids Mode", isPresented: $showExitPin) {
                TextField("4-digit PIN", text: $pinEntry)
                    .keyboardType(.numberPad)
                Button("Exit") {
                    if kids.disable(pin: pinEntry) {
                        pinEntry = ""
                        dismiss()
                    } else {
                        pinEntry = ""
                        showWrongPin = true
                    }
                }
                Button("Cancel", role: .cancel) { pinEntry = "" }
            }
            .alert("Wrong PIN", isPresented: $showWrongPin) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Kids Mode stays on.")
            }
        }
    }
}
