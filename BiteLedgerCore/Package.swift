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
    dependencies: [
        .package(url: "https://github.com/weichsel/ZipFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "BiteLedgerCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZipFoundation")],
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
