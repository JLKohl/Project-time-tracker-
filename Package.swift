// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProjectTimeTracker",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    ],
    targets: [
        // All tracking logic and storage. Has no UI code, so it can be tested on its own.
        .target(name: "TimeTrackerCore"),
        .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"]),
    ]
)
