// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Dose",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Dose",
            path: "Sources/Dose",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
