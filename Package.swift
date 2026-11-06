// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Island", path: "Sources/Island")
    ]
)
