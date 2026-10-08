// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Dice", platforms: [.macOS(.v14)], products: [.executable(name: "Dice", targets: ["Dice"])], targets: [.target(name: "DiceCore"), .executableTarget(name: "Dice", dependencies: ["DiceCore"]), .executableTarget(name: "DiceChecks", dependencies: ["DiceCore"], path: "Tests/DiceCoreTests")])
