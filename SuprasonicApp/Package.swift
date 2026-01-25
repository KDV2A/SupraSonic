// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SupraSonicApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SupraSonicApp", targets: ["SupraSonicApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "SupraSonicCoreFFI",
            dependencies: [],
            path: "Sources/SupraSonicCoreFFI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SupraSonicCore",
            dependencies: ["SupraSonicCoreFFI"],
            path: "Sources/SupraSonicCore"
        ),
        .executableTarget(
            name: "SupraSonicApp",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                "SupraSonicCore"
            ],
            path: "Sources",
            exclude: ["SupraSonicCore", "SupraSonicCoreFFI"], // Exclude the nested directory from the main target sources
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__entitlements", "-Xlinker", "SupraSonicApp.entitlements",
                    "-L./Libs", "-lsuprasonic_core",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path" 
                ])
            ]
        )
    ]
)
