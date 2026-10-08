// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dice",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Dice", targets: ["Dice"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "DiceCore"),
        .executableTarget(name: "Dice", dependencies: ["DiceCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "DiceChecks", dependencies: ["DiceCore"], path: "Tests/DiceCoreTests")
    ]
)
