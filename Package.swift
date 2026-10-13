// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AutoCorrection",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AutoCorrection", path: "Sources/AutoCorrection")
    ]
)
