// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UptimeBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UptimeBar",
            path: "Sources",
            exclude: ["Resources"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Resources/Info.plist"
                ])
            ]
        )
    ]
)
