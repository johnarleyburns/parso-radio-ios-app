import Foundation

// MARK: - ChannelDefinition model (mirrors CustomChannelsStore)

struct ChannelDefinition: Codable, Equatable {
    struct Info: Codable, Equatable {
        let id: String
        let name: String
        let icon: String
        let iaQuery: String?
    }
    struct ApprovedEntry: Codable, Equatable {
        let id: String
        let title: String
        let creator: String
        let duration: Double
        let parentIdentifier: String?
    }
    let version: Int
    var channel: Info
    var updatedAt: String
    var approved: [ApprovedEntry]
    var rejected: [String]
}

// MARK: - Merge engine

enum Operation: String {
    case merge
    case replace
}

struct Diff {
    let operation: Operation
    let added: Int
    let skipped: Int
    let totalAfter: Int
}

func apply(input: ChannelDefinition, target: ChannelDefinition, mode: Operation) -> (ChannelDefinition, Diff) {
    switch mode {
    case .replace:
        var result = input
        result.channel = target.channel       // Preserve hand-maintained channel info
        result.updatedAt = ISO8601DateFormatter().string(from: Date())
        let diff = Diff(operation: .replace, added: 0, skipped: 0, totalAfter: result.approved.count)
        return (result, diff)

    case .merge:
        var merged = target
        let existingIds = Set(target.approved.map(\.id))
        var added = 0
        var skipped = 0
        for entry in input.approved {
            if existingIds.contains(entry.id) {
                skipped += 1
            } else {
                merged.approved.append(entry)
                added += 1
            }
        }
        merged.updatedAt = ISO8601DateFormatter().string(from: Date())
        let diff = Diff(operation: .merge, added: added, skipped: skipped, totalAfter: merged.approved.count)
        return (merged, diff)
    }
}

func readJSON(path: String) -> ChannelDefinition? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        fputs("error: cannot read file at \(path)\n", stderr)
        return nil
    }
    guard let def = try? JSONDecoder().decode(ChannelDefinition.self, from: data) else {
        fputs("error: cannot parse JSON at \(path) — is it a valid ChannelDefinition?\n", stderr)
        return nil
    }
    return def
}

func writeJSON(def: ChannelDefinition, to path: String) {
    var writable = def
    writable.updatedAt = ISO8601DateFormatter().string(from: Date())
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(writable) else {
        fputs("error: failed to encode output JSON\n", stderr)
        return
    }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

// MARK: - CLI entry

func main() {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        printUsage()
        return
    }

    var dryRun = false
    var mode: Operation?
    var inputPath: String?
    var targetPath: String?

    var i = 1
    while i < args.count {
        switch args[i] {
        case "merge":
            mode = .merge
        case "replace":
            mode = .replace
        case "--dry-run":
            dryRun = true
        case "--input":
            i += 1
            if i < args.count { inputPath = args[i] }
        case "--target":
            i += 1
            if i < args.count { targetPath = args[i] }
        case "--help", "-h":
            printUsage()
            return
        default:
            fputs("warning: unknown argument \(args[i])\n", stderr)
        }
        i += 1
    }

    guard let mode, let inputPath, let targetPath else {
        printUsage()
        return
    }

    guard let input = readJSON(path: inputPath) else { exit(1) }
    guard let target = readJSON(path: targetPath) else { exit(1) }

    let (result, diff) = apply(input: input, target: target, mode: mode)

    print("mode:          \(diff.operation.rawValue)")
    if diff.operation == .merge {
        print("input entries: \(input.approved.count)")
        print("target before: \(target.approved.count)")
        print("added:         \(diff.added)")
        print("skipped:       \(diff.skipped)")
    }
    print("total after:   \(diff.totalAfter)")

    if dryRun {
        print("\n[dry-run] No files written.")
    } else {
        writeJSON(def: result, to: targetPath)
        print("\nWritten to \(targetPath)")
    }
}

func printUsage() {
    print("""
    merge-curation — Merge or replace curated channel defaults from an exported JSON.

    USAGE:
      merge-curation merge   --input <exported.json> --target <bundled.json> [--dry-run]
      merge-curation replace --input <exported.json> --target <bundled.json> [--dry-run]

    MODES:
      merge     Add new approved entries from --input to --target (skip duplicates).
                Preserves all existing target channel metadata (name, icon, iaQuery).

      replace   Completely overwrite --target's approved list with entries from --input.
                Preserves the target's channel info (name, icon, iaQuery).
                Useful when you've heavily re-curated a channel from the app.

    OPTIONS:
      --dry-run   Print what WOULD happen without writing any files.
      --help      Show this message.

    EXAMPLES:
      # Add newly-curated tracks to the Classical Guitar default:
      merge-curation merge \\
        --input ~/Downloads/guitar-classical.json \\
        --target Resources/curated-channels/guitar-classical.json

      # See what the merge would do before committing:
      merge-curation merge --dry-run \\
        --input ~/Downloads/guitar-classical.json \\
        --target Resources/curated-channels/guitar-classical.json

      # Full replacement after heavy re-curation:
      merge-curation replace \\
        --input ~/Downloads/guitar-classical.json \\
        --target Resources/curated-channels/guitar-classical.json
    """)
}

main()
