import Foundation

enum ComposerMap {
    static let aliases: [String: String] = [
        "bach": "bach", "j.s. bach": "bach", "j. s. bach": "bach",
        "johann sebastian bach": "bach", "bach, johann sebastian": "bach",
        "vivaldi": "vivaldi", "antonio vivaldi": "vivaldi",
        "a. vivaldi": "vivaldi", "vivaldi, antonio": "vivaldi",
        "chopin": "chopin", "f. chopin": "chopin",
        "frederic chopin": "chopin", "frédéric chopin": "chopin",
        "chopin, frederic": "chopin",
        "rachmaninoff": "rachmaninoff", "rachmaninov": "rachmaninoff",
        "s. rachmaninoff": "rachmaninoff", "sergei rachmaninoff": "rachmaninoff",
        "sergei rachmaninov": "rachmaninoff",
    ]

    static let similarity: [String: [String]] = [
        "bach":         ["vivaldi", "handel", "telemann", "scarlatti"],
        "vivaldi":      ["bach", "handel", "corelli"],
        "chopin":       ["rachmaninoff", "liszt", "schumann"],
        "rachmaninoff": ["chopin", "tchaikovsky", "scriabin"],
    ]

    static func normalize(_ raw: String) -> String? {
        aliases[raw.lowercased().trimmingCharacters(in: .whitespaces)]
    }
}
