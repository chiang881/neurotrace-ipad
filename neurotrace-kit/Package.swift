// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NeuroTraceKit",
    platforms: [.iOS("26.5"), .macOS(.v12)],
    products: [
        .library(name: "NeuroTraceDomain", targets: ["NeuroTraceDomain"]),
        .library(name: "NeuroTraceApplication", targets: ["NeuroTraceApplication"]),
        .library(name: "NeuroTraceInfrastructure", targets: ["NeuroTraceInfrastructure"]),
        .library(name: "NeuroTraceUIKit", targets: ["NeuroTraceUIKit"])
    ],
    targets: [
        .target(name: "NeuroTraceDomain"),
        .target(name: "NeuroTraceApplication", dependencies: ["NeuroTraceDomain"]),
        .target(name: "NeuroTraceInfrastructure", dependencies: ["NeuroTraceApplication"]),
        .target(name: "NeuroTraceUIKit", dependencies: ["NeuroTraceApplication"]),
        .testTarget(name: "NeuroTraceApplicationTests", dependencies: ["NeuroTraceApplication"])
    ]
)
