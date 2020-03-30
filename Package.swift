// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "docker",
    platforms: [.macOS(.v10_15)],
    products: [.executable(name: "buildAndTag", targets: ["BuildAndTagExecutable"])],
    dependencies: [
        .package(url: "https://github.com/vapor/console-kit.git", from: "4.0.0"),
    ],
    targets: [
        .target(name: "BuildAndTag", dependencies: [.product(name: "ConsoleKit", package: "console-kit")]),
        .target(name: "BuildAndTagExecutable", dependencies: ["BuildAndTag"]),
    ]
)
