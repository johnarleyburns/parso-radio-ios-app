import SwiftUI

/// Text that truncates to a given number of lines by default, with a
/// "more" / "less" toggle to expand or collapse.
struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 4

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : lineLimit)

            if needsExpansion {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation { expanded.toggle() }
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
        }
    }

    private var needsExpansion: Bool {
        // Simple heuristic: if text has more than ~3 lines worth of content
        let lineCount = text.components(separatedBy: .newlines).count
        let charCount = text.count
        return lineCount > lineLimit || charCount > lineLimit * 50
    }
}
