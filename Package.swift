// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FolioVoice",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FolioCore", targets: ["FolioCore"])],
    targets: [
        .target(name: "FolioCore", path: "FolioVoice/Core"),
        .executableTarget(name: "FolioCoreSmokeCheck", dependencies: ["FolioCore"], path: "Tests/FolioCoreSmokeCheck"),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"], path: "Tests/FolioCoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
