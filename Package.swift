// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quoted",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Quoted", targets: ["Quoted"])],
    targets: [
        .target(name: "QuotedCore"),
        .executableTarget(name: "Quoted", dependencies: ["QuotedCore"]),
        .testTarget(name: "QuotedCoreTests", dependencies: ["QuotedCore"])
    ],
    swiftLanguageModes: [.v5]
)
