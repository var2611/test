// swift-tools-version: 5.9
import PackageDescription

// WattsonCore is deliberately UI-free and IOKit-free so that all of the decision
// logic in the app can be built and unit-tested with plain `swift test` on any
// machine, independent of Xcode and independent of the hardware it runs on.
//
// The macOS application target lives in ./App and is built through the Xcode
// project generated from project.yml (see README.md).
let package = Package(
    name: "Wattson",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WattsonCore", targets: ["WattsonCore"])
    ],
    targets: [
        .target(name: "WattsonCore", path: "Sources/WattsonCore"),
        .testTarget(
            name: "WattsonCoreTests",
            dependencies: ["WattsonCore"],
            path: "Tests/WattsonCoreTests"
        )
    ]
)
