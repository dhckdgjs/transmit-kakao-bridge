// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TransmitDropProbe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TransmitDropProbe", targets: ["TransmitDropProbe"]),
        .executable(name: "TransmitKakaoBridge", targets: ["TransmitKakaoBridge"])
    ],
    targets: [
        .executableTarget(
            name: "TransmitDropProbe"
        ),
        .executableTarget(
            name: "TransmitKakaoBridge"
        )
    ]
)
