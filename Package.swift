// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do checkout do neyhub ao lado (ou NEYHUB_PATH). A identidade de `.package(path:)` é o nome
// da pasta em minúsculas, então derivamos dela: funciona com worktrees.
let neyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub"
let hub = URL(fileURLWithPath: neyhub).lastPathComponent.lowercased()
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Dose",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dose", targets: ["Dose"]),
        .library(name: "DosePlugin", type: .dynamic, targets: ["DosePlugin"]),
    ],
    dependencies: [.package(path: neyhub)],
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
