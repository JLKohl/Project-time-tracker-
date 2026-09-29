// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProjectTimeTracker",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ProjectTimeTracker", targets: ["ProjectTimeTracker"]),
        .library(name: "TimeTrackerCore", targets: ["TimeTrackerCore"]),
    ],
    targets: [
        // All tracking logic and storage. Has no UI code, so it can be tested on its own.
        .target(name: "TimeTrackerCore"),
        // The menu bar app itself.
        .executableTarget(name: "ProjectTimeTracker", dependencies: ["TimeTrackerCore"]),
        .testTarget(name: "TimeTrackerCoreTests", dependencies: ["TimeTrackerCore"]),
    ]
)
