// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Murmur", targets: ["Murmur"])],
    dependencies: [
        // Local, open-source Whisper speech recognition (MIT). Pinned for reproducible builds.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "MurmurCore"),
        .executableTarget(name: "Murmur", dependencies: ["MurmurCore", .product(name: "WhisperKit", package: "WhisperKit")]),
        .executableTarget(name: "MurmurChecks", dependencies: ["MurmurCore"], path: "Tests/MurmurCoreTests"),
    ]
)
