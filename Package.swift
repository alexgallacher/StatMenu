// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StatMenu",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CStats",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(
            name: "StatMenu",
            dependencies: ["CStats"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
