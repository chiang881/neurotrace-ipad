// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParchmentKit",
    platforms: [.iOS("26.5"), .macOS(.v12)],
    products: [
        .library(name: "ParchmentDomain", targets: ["ParchmentDomain"]),
        .library(name: "ParchmentApplication", targets: ["ParchmentApplication"]),
        .library(name: "ParchmentInfrastructure", targets: ["ParchmentInfrastructure"]),
        .library(name: "ParchmentUIKit", targets: ["ParchmentUIKit"])
    ],
    targets: [
        .target(name: "ParchmentDomain"),
        .target(name: "ParchmentApplication", dependencies: ["ParchmentDomain"]),
        .target(name: "ParchmentInfrastructure", dependencies: ["ParchmentApplication"]),
        .target(name: "ParchmentUIKit", dependencies: ["ParchmentApplication"]),
        .testTarget(name: "ParchmentApplicationTests", dependencies: ["ParchmentApplication"])
    ]
)
