// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Macdow",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Macdow",
            path: "Sources/Macdow"
        )
    ]
)
