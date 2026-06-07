// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "merge-curation",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "merge-curation",
            path: "Sources/merge-curation"
        )
    ]
)
