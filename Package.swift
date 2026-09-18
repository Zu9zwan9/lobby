// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lobby",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LobbyCore"),
        .executableTarget(name: "Lobby", dependencies: ["LobbyCore"]),
        .executableTarget(name: "LobbyCheck", dependencies: ["LobbyCore"]),
        .testTarget(name: "LobbyCoreTests", dependencies: ["LobbyCore"]),
    ]
)
