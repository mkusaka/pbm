// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "pbm",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "pbw", targets: ["pbw"]),
        .library(name: "PBWCore", targets: ["PBWCore"]),
    ],
    targets: [
        .target(
            name: "PBWCore",
            path: "macos/Sources/PBWCore",
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
            name: "pbw",
            dependencies: ["PBWCore"],
            path: "macos/Sources/pbw",
        ),
        .testTarget(
            name: "PBWCoreTests",
            dependencies: ["PBWCore"],
            path: "macos/Tests/PBWCoreTests",
        ),
    ],
)
