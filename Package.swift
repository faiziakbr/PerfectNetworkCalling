// swift-tools-version: 6.2
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    // Same behaviour as the Xcode project's "Approachable Concurrency" setting
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "PerfectNetworkCalling",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PerfectNetworkCalling", targets: ["PerfectNetworkCalling"]),
    ],
    targets: [
        .target(
            name: "PerfectNetworkCalling",
            path: "PerfectNetworkCalling",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "PerfectNetworkCallingTests",
            dependencies: ["PerfectNetworkCalling"],
            path: "PerfectNetworkCallingTests",
            swiftSettings: concurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)