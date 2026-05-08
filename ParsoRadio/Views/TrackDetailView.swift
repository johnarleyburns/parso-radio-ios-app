import SwiftUI

struct TrackDetailView: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Track") {
                    labeledRow("Title", value: track.title)
                    labeledRow("Artist", value: track.artist)
                    if let composer = track.composer, !composer.isEmpty {
                        labeledRow("Composer", value: composer.capitalized)
                    }
                    if !track.instruments.isEmpty {
                        labeledRow("Instruments", value: track.instruments.joined(separator: ", "))
                    }
                    if track.duration > 0 {
                        labeledRow("Duration", value: formatTime(track.duration))
                    }
                }

                Section("Rights") {
                    HStack {
                        Text("License").foregroundStyle(.secondary)
                        Spacer()
                        licenseView(track.license)
                    }
                    HStack {
                        Text("Source").foregroundStyle(.secondary)
                        Spacer()
                        sourceView(track.source)
                    }
                }

                Section {
                    if let url = sourceURL {
                        Link("Open on \(sourceName)", destination: url)
                            .foregroundStyle(Color.accentColor)
                    }
                    Link(audioFileLabel, destination: track.streamURL)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Track Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func licenseView(_ license: LicenseType) -> some View {
        switch license {
        case .cc0:          badge("CC0", color: .blue)
        case .ccBy:         badge("CC BY", color: .orange)
        case .publicDomain: badge("Public Domain", color: .green)
        case .rejected:     Text("Unknown").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sourceView(_ source: String) -> some View {
        switch source {
        case "fma":              badge("Free Music Archive", color: .green)
        case "musopen":          badge("Musopen", color: .purple)
        case "internet_archive": badge("Internet Archive", color: .gray)
        case "oxford_lectures":  badge("Oxford University", color: Color(red: 0.00, green: 0.13, blue: 0.28))
        default:                 badge(source, color: .gray)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var sourceURL: URL? {
        switch track.source {
        case "internet_archive":
            return URL(string: "https://archive.org/details/\(track.id)")
        case "fma":
            // FMA streamURL is https://freemusicarchive.org/track/{handle}/stream/
            // Remove the /stream/ suffix to get the track page.
            let streamStr = track.streamURL.absoluteString
            return URL(string: streamStr.replacingOccurrences(of: "/stream/", with: "/"))
        default:
            return nil
        }
    }

    private var audioFileLabel: String {
        switch track.source {
        case "internet_archive": return "Audio Files (Internet Archive)"
        case "fma":              return "Stream on Free Music Archive"
        case "oxford_lectures":  return "Audio File (Oxford)"
        default:                 return "Audio File"
        }
    }

    private var sourceName: String {
        switch track.source {
        case "internet_archive": return "Internet Archive"
        case "fma":              return "Free Music Archive"
        case "musopen":          return "Musopen"
        default:                 return "Source"
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "—" }
        let t = Int(s)
        let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}

#Preview {
    TrackDetailView(track: Track(
        id: "archive-sample",
        source: "internet_archive",
        title: "Brandenburg Concerto No. 3 in G major, BWV 1048",
        artist: "Musica Antiqua Köln",
        duration: 823,
        streamURL: URL(string: "https://archive.org/download/sample")!,
        downloadURL: nil,
        localFilePath: nil,
        license: .publicDomain,
        tags: ["classical", "baroque"],
        qualityScore: 0.9,
        rawCreator: "bach",
        composer: "bach",
        instruments: ["strings", "harpsichord"],
        metadataConfidence: 3.0
    ))
}
