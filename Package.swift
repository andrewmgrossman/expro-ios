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
        ),
        .library(
            name: "ExProSupport",
            targets: ["ExProSupport"]
        ),
        .executable(
            name: "DevialetTools",
            targets: ["DevialetTools"]
        )
    ],
    targets: [
        .target(
            name: "DevialetCore"
        ),
        .target(
            name: "ExProSupport",
            dependencies: ["DevialetCore"],
            path: "ExProApp",
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "DevialetExpertControlApp.swift",
                "DiagnosticsView.swift",
                "Info.plist",
                "SettingsView.swift"
            ],
            sources: [
                "AppStateStore.swift",
                "VolumeSettings.swift"
            ]
        ),
        .executableTarget(
            name: "DevialetTools",
            dependencies: ["DevialetCore"]
        ),
        .testTarget(
            name: "DevialetCoreTests",
            dependencies: ["DevialetCore"],
            resources: [
                .copy("Fixtures/status_fixture_1.bin")
            ]
        ),
        .testTarget(
            name: "ExProSupportTests",
            dependencies: ["ExProSupport", "DevialetCore"]
        )
    ]
)
