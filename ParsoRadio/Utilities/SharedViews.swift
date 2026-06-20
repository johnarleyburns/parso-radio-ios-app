import SwiftUI

enum SharedViews {}

extension SharedViews {
    static func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    static func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

enum LicenseDisplay {
    static func name(_ license: LicenseType) -> String {
        switch license {
        case .cc0:          return "CC0"
        case .ccBy:         return "CC BY"
        case .publicDomain: return "Public Domain"
        case .rejected:     return "Unknown"
        }
    }

    @ViewBuilder
    static func label(_ license: LicenseType) -> some View {
        switch license {
        case .cc0:
            SharedViews.badge("CC0", color: .blue)
        case .ccBy:
            SharedViews.badge("CC BY", color: .orange)
        case .publicDomain:
            SharedViews.badge("Public Domain", color: .green)
        case .rejected:
            EmptyView()
        }
    }
}

enum SourceDisplay {
    static func name(_ source: String) -> String {
        switch source {
        case "internet_archive": return "Internet Archive"
        case "fma":              return "Free Music Archive"
        case "oxford_lectures":  return "Oxford University"
        case "podcast":          return "Podcast"
        case "nps":              return "National Park Service"
        case "freesound":        return "Freesound"
        case "local":            return "My Files"
        default:                  return source
        }
    }

    @ViewBuilder
    static func tag(_ source: String) -> some View {
        switch source {
        case "fma":
            SharedViews.badge("Free Music Archive", color: .gray)
        case "musopen":
            SharedViews.badge("Musopen", color: .purple)
        case "podcast":
            SharedViews.badge("Podcast", color: Color(red: 0.10, green: 0.20, blue: 0.40))
        case "nps":
            SharedViews.badge("NPS", color: Color(red: 0.08, green: 0.38, blue: 0.28))
        case "freesound":
            SharedViews.badge("Freesound", color: Color(red: 0.08, green: 0.38, blue: 0.28))
        default:
            SharedViews.badge("Internet Archive", color: .gray)
        }
    }
}

enum BrandGradient {
    static let linear = LinearGradient(
        colors: [Color(red: 0.42, green: 0.20, blue: 0.80),
                 Color(red: 0.10, green: 0.22, blue: 0.65)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let topColor = Color(red: 0.42, green: 0.20, blue: 0.80)
    static let bottomColor = Color(red: 0.10, green: 0.22, blue: 0.65)
}

