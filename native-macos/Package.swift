// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "MIMIGuitarMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MIMIGuitarMac", targets: ["MIMIGuitarMac"]),
        .library(name: "MIMICore", targets: ["MIMICore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(
            name: "MIMICore",
            dependencies: ["CSQLite"],
            path: "Sources/MIMICore",
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .executableTarget(
            name: "MIMIGuitarMac",
            dependencies: ["MIMICore"],
            path: "Sources/MIMIGuitarMac"
        ),
    ]
)
