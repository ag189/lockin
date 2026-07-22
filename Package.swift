// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lockin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Lockin", targets: ["Lockin"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "Lockin",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Lockin"
        ),
        .testTarget(
            name: "LockinTests",
            dependencies: ["Lockin"],
            path: "Tests/LockinTests"
        )
    ]
)
