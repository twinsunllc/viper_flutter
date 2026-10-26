// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "viper_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "viper-flutter", targets: ["viper_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "viper_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
