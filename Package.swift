// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CherryPicker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CherryPickerCore",
            targets: ["CherryPickerCore"]
        ),
        .library(
            name: "CherryPickerServer",
            targets: ["CherryPickerServer"]
        ),
        .executable(
            name: "CherryPickerLocalServer",
            targets: ["CherryPickerLocalServer"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            .upToNextMinor(from: "2.22.0")
        )
    ],
    targets: [
        .target(
            name: "CherryPickerCore"
        ),
        .target(
            name: "CherryPickerServer",
            dependencies: [
                "CherryPickerCore",
                .product(name: "Hummingbird", package: "hummingbird")
            ]
        ),
        .executableTarget(
            name: "CherryPickerLocalServer",
            dependencies: [
                "CherryPickerServer",
                .product(name: "Hummingbird", package: "hummingbird")
            ]
        ),
        .testTarget(
            name: "CherryPickerCoreTests",
            dependencies: ["CherryPickerCore"]
        ),
        .testTarget(
            name: "CherryPickerServerTests",
            dependencies: [
                "CherryPickerServer",
                "CherryPickerCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ]
        )
    ]
)
