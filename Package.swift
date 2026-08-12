// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AIUsageMonitor",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "AIUsageMonitor", targets: ["AIUsageMonitor"]),
    .executable(name: "AIUsageCollector", targets: ["AIUsageCollector"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle",
      exact: "2.9.5"
    )
  ],
  targets: [
    .executableTarget(
      name: "AIUsageMonitor",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle")
      ],
      path: "Sources/AIUsageMonitor"
    ),
    .executableTarget(
      name: "AIUsageCollector",
      path: "Sources/AIUsageCollector"
    ),
    .testTarget(
      name: "AIUsageMonitorTests",
      dependencies: ["AIUsageMonitor"],
      path: "Tests/AIUsageMonitorTests"
    ),
  ]
)
