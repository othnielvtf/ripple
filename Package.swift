// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ripple",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ripple", targets: ["Ripple"])],
    targets: [.executableTarget(name: "Ripple", path: "Sources/Ripple")]
)
