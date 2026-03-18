// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WisprNative",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Flow", targets: ["WisprMenuBar"]),
    ],
    targets: [
        .executableTarget(
            name: "WisprMenuBar"
        ),
    ]
)
