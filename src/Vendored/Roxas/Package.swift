// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "Roxas",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "Roxas",
            targets: ["Roxas"]
        ),
    ],
    targets: [
        .target(
            name: "Roxas",
            path: "Sources/Roxas",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("include/Roxas"),
            ],
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
                .linkedFramework("Foundation"),
                .linkedFramework("CoreData"),
            ]
        ),
    ]
)
