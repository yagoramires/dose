// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do neyhub publicado no GitHub. Para desenvolver junto com um checkout local: NEYHUB_PATH=../neyhub
// (a identidade de `.package(path:)` é o nome da pasta em minúsculas, então derivamos dela: funciona com worktrees).
let localNeyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"]
let hub = localNeyhub.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? "neyhub"
let neyhubPackage: Package.Dependency = localNeyhub.map { .package(path: $0) }
    ?? .package(url: "https://github.com/yagoramires/neyhub.git", from: "0.1.0")
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Dose",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dose", targets: ["Dose"]),
        .library(name: "DosePlugin", type: .dynamic, targets: ["DosePlugin"]),
    ],
    dependencies: [neyhubPackage],
    targets: [
        .target(name: "DoseCore", dependencies: [.product(name: "NeyKit", package: hub)], path: "Sources/DoseCore", swiftSettings: swift5),
        .executableTarget(
            name: "Dose",
            dependencies: ["DoseCore", .product(name: "NeyKitApp", package: hub)],
            path: "Sources/Dose",
            swiftSettings: swift5
        ),
        // Plugin do NeyHub: nunca linka NeyKitApp (classes duplicadas no processo do NeyHub).
        .target(name: "DosePlugin", dependencies: ["DoseCore", .product(name: "NeyKit", package: hub)], path: "Sources/DosePlugin", swiftSettings: swift5),
    ]
)
