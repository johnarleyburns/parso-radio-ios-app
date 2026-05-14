import SwiftUI
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    let allowedTypes: [UTType]
    let allowsMultipleSelection: Bool
    var asCopy: Bool = true
    let onPickedURLs: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: allowedTypes,
            asCopy: asCopy
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPickedURLs: onPickedURLs) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPickedURLs: ([URL]) -> Void
        init(onPickedURLs: @escaping ([URL]) -> Void) { self.onPickedURLs = onPickedURLs }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPickedURLs(urls)
        }
    }
}
