// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    targets: [
        .target(name: "CoreKit", path: "Sources/CoreKit")
    ]
)
