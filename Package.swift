// swift-tools-version:5.7
import PackageDescription

let dependencies: [Package.Dependency]
#if swift(>=5.6) && swift(<5.7) && os(macOS)
dependencies = [.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")]
#else
dependencies = []
#endif

let package = Package(
    name: "Yams",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Yams", targets: ["Yams"]),
        .executable(name: "yams-cli", targets: ["yams-cli"])
    ],
    dependencies: dependencies,
    targets: [
        .executableTarget(
            name: "yams-cli",
            dependencies: ["Yams"]
        ),
        .target(
            name: "CYaml",
            exclude: ["CMakeLists.txt"],
            cSettings: [.define("YAML_DECLARE_EXPORT")]
        ),
        .target(
            name: "Yams",
            dependencies: ["CYaml"],
            exclude: ["CMakeLists.txt"]
        )
    ]
)
