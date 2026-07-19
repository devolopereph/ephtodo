// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "multi_window_manager",
  platforms: [
    .macOS("10.14"),
  ],
  products: [
    .library(name: "multi-window-manager", targets: ["multi_window_manager"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "multi_window_manager",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ]
    ),
  ]
)
