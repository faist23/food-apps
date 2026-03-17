// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BiteLedgerCore",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "BiteLedgerCore",
            targets: ["BiteLedgerCore"]
        ),
    ],
    targets: [
        .target(
            name: "BiteLedgerCore",
            dependencies: [],
            path: "Sources/BiteLedgerCore",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
