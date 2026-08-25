// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExtractrKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ExtractrKit", targets: ["ExtractrKit"]),
    ],
    targets: [
        .target(name: "ExtractrKit"),
        .testTarget(name: "ExtractrKitTests", dependencies: ["ExtractrKit"]),
    ]
)
