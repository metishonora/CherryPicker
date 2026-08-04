// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CherryPicker",
    platforms: [
        .iOS("27.0"),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CherryPickerCore",
            targets: ["CherryPickerCore"]
        )
    ],
    targets: [
        .target(
            name: "CherryPickerCore"
        ),
        .testTarget(
            name: "CherryPickerCoreTests",
            dependencies: ["CherryPickerCore"]
        )
    ]
)
