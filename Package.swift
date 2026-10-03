// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokPlanSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GrokPlanSwitcher", targets: ["GrokPlanSwitcher"])
    ],
    targets: [
        .executableTarget(name: "GrokPlanSwitcher"),
        .testTarget(name: "GrokPlanSwitcherTests", dependencies: ["GrokPlanSwitcher"])
    ]
)
