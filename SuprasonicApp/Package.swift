// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SuprasonicApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SuprasonicApp", targets: ["SuprasonicApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "SuprasonicApp",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__entitlements", "-Xlinker", "SuprasonicApp.entitlements"])
            ]
        )
    ]
)
