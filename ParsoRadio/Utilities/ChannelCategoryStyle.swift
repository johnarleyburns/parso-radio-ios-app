import SwiftUI

enum ChannelCategoryStyle {
    static func color(for category: String) -> Color {
        switch category {
        case "Classical":    return Color(red: 0.42, green: 0.20, blue: 0.80)
        case "Audiobooks":   return Color(red: 0.55, green: 0.35, blue: 0.10)
        case "Contemporary": return Color(red: 0.20, green: 0.40, blue: 0.20)
        case "Lectures":     return Color(red: 0.00, green: 0.13, blue: 0.28)
        case "News":         return Color(red: 0.10, green: 0.20, blue: 0.40)
        case "Ambient":      return Color(red: 0.08, green: 0.38, blue: 0.28)
        default:             return Color(red: 0.20, green: 0.25, blue: 0.35)
        }
    }

    static func gradient(for category: String) -> LinearGradient {
        let (top, bottom): (Color, Color)
        switch category {
        case "Classical":
            top = Color(red: 0.42, green: 0.20, blue: 0.80)
            bottom = Color(red: 0.62, green: 0.10, blue: 0.52)
        case "Audiobooks":
            top = Color(red: 0.55, green: 0.35, blue: 0.10)
            bottom = Color(red: 0.80, green: 0.55, blue: 0.20)
        case "Contemporary":
            top = Color(red: 0.20, green: 0.40, blue: 0.20)
            bottom = Color(red: 0.35, green: 0.65, blue: 0.30)
        case "Lectures":
            top = Color(red: 0.00, green: 0.13, blue: 0.28)
            bottom = Color(red: 0.50, green: 0.38, blue: 0.10)
        case "News":
            top = Color(red: 0.10, green: 0.20, blue: 0.40)
            bottom = Color(red: 0.20, green: 0.40, blue: 0.60)
        case "Ambient":
            top = Color(red: 0.08, green: 0.38, blue: 0.28)
            bottom = Color(red: 0.18, green: 0.58, blue: 0.42)
        default:
            top = Color.gray
            bottom = Color.gray.opacity(0.6)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func icon(for category: String) -> String {
        switch category {
        case "Playlists":     return "music.note.list"
        case "Curated":       return "star.fill"
        case "Ambient":       return "leaf.fill"
        case "News":          return "newspaper.fill"
        case "Audiobooks":    return "book.fill"
        case "Lectures":      return "building.columns.fill"
        default:              return "music.note"
        }
    }
}
