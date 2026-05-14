// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "pbm",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "pbm", targets: ["pbm"]),
        .library(name: "PBMCore", targets: ["PBMCore"]),
    ],
    targets: [
        .target(
            name: "PBMCore",
            path: "macos/Sources/PBMCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ],
        ),
        .executableTarget(
            name: "pbm",
            dependencies: ["PBMCore"],
            path: "macos/Sources/pbm",
        ),
        .testTarget(
            name: "PBMCoreTests",
            dependencies: ["PBMCore"],
            path: "macos/Tests/PBMCoreTests",
        ),
    ],
)
