// swift-tools-version: 5.9

import PackageDescription

// Swift Package Manager support, alongside the podspec one directory up. Both
// build the same sources under Sources/, so there is one copy of the plugin and
// a host can integrate it either way. Flutter warns on every build for a plugin
// that offers only CocoaPods, and has said that will become an error.
//
// The product name is the package name with hyphens. FlutterFramework is a
// relative path dependency Flutter materialises next to this package when it
// generates the app's plugin package; Flutter 3.47 warns on every build for a
// plugin that omits it.
let package = Package(
    name: "adadapted_flutter_sdk",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(name: "adadapted-flutter-sdk", targets: ["adadapted_flutter_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "adadapted_flutter_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
