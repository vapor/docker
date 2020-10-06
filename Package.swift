// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "docker",
    platforms: [.macOS(.v10_15)],
    dependencies: [
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/leaf-kit.git", from: "1.0.0-rc"),
    ],
    targets: [
        .target(name: "BuildAndTagScript", dependencies: [
            .product(name: "ConsoleKit", package: "console-kit"),
            .product(name: "LeafKit", package: "leaf-kit"),
        ]),
        .target(name: "buildAndTag", dependencies: ["BuildAndTagScript"]),
    ]
)
