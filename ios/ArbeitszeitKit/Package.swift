// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ArbeitszeitKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ArbeitszeitKit", targets: ["ArbeitszeitKit"]),
    ],
    targets: [
        .target(
            name: "ArbeitszeitKit",
            path: "Sources/ArbeitszeitKit"
        ),
        .testTarget(
            name: "ArbeitszeitKitTests",
            dependencies: ["ArbeitszeitKit"],
            path: "Tests/ArbeitszeitKitTests"
        ),
    ]
)
