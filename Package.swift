// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevialetIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DevialetCore",
            targets: ["DevialetCore"]
        )
    ],
    targets: [
        .target(
            name: "DevialetCore"
        ),
        .testTarget(
            name: "DevialetCoreTests",
            dependencies: ["DevialetCore"],
            resources: [
                .copy("Fixtures/status_fixture_1.bin")
            ]
        )
    ]
)
