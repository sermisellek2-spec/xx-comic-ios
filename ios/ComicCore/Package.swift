// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComicCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ComicCore", targets: ["ComicCore"])],
    targets: [
        .target(name: "ComicCore"),
        .testTarget(name: "ComicCoreTests", dependencies: ["ComicCore"], resources: [.copy("Fixtures/manwa"), .copy("Fixtures/copy4000")])
    ]
)
