// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpotifyIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpotifyIsland",
            path: "SpotifyIsland",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "SpotifyIsland.entitlements"
            ]
        )
    ]
)
