// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComicCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ComicCore", targets: ["ComicCore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .systemLibrary(name: "ComicZlib", pkgConfig: "zlib", providers: [.apt(["zlib1g-dev"])]),
        .target(name: "ComicCore", dependencies: ["ComicZlib", .product(name: "ZIPFoundation", package: "ZIPFoundation")], resources: [.copy("Resources/ZIPFoundation-LICENSE.txt"), .copy("Resources/public-sources.json")]),
        .testTarget(
            name: "ComicCoreTests",
            dependencies: ["ComicCore"],
            resources: [
                .copy("Fixtures/manwa"),
                .copy("Fixtures/copy4000"),
                .copy("Fixtures/new-sources"),
                .copy("Fixtures/public-sources"),
                .copy("Fixtures/dongmanla-44074.html")
            ]
        )
    ]
)
