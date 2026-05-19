// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ogg_record_player",
  platforms: [
    .iOS(.v13),
  ],
  products: [
    .library(name: "ogg-record-player", targets: ["ogg_record_player"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .binaryTarget(name: "libogg", path: "Frameworks/libogg.xcframework"),
    .binaryTarget(name: "libopus", path: "Frameworks/libopus.xcframework"),
    .binaryTarget(name: "libopusenc", path: "Frameworks/libopusenc.xcframework"),
    .binaryTarget(name: "libopusfile", path: "Frameworks/libopusfile.xcframework"),
    .target(
      name: "ogg_record_player_c",
      dependencies: [],
      path: "Sources/ogg_record_player_c",
      publicHeadersPath: "include",
      cSettings: [
        .headerSearchPath(".")
      ]
    ),
    .target(
      name: "ogg_record_player",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        "ogg_record_player_c",
        "libogg",
        "libopus",
        "libopusenc",
        "libopusfile",
      ],
      path: "Sources/ogg_record_player"
    ),
  ]
)

