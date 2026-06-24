// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whispurr",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "WhispurrCore", targets: ["WhispurrCore"]),
        .library(name: "WhispurrPipeline", targets: ["WhispurrPipeline"]),
        .executable(name: "Whispurr", targets: ["WhispurrApp"]),
    ],
    targets: [
        .target(name: "WhispurrCore"),
        .target(name: "WhispurrPipeline", dependencies: ["WhispurrCore"]),
        .executableTarget(
            name: "WhispurrApp",
            dependencies: ["WhispurrCore", "WhispurrPipeline"],
            exclude: ["Info.plist"],
            resources: [.copy("Resources/CatFrames")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/WhispurrApp/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "WhispurrCoreTests", dependencies: ["WhispurrCore"]),
        .testTarget(name: "WhispurrPipelineTests", dependencies: ["WhispurrPipeline"]),
    ]
)
