// swift-tools-version: 5.9

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MYMS",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "MYMS",
            targets: ["AppModule"],
            bundleIdentifier: "edu.myms.fitness",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            additionalInfoPlistContentFilePath: "AppInfo.plist"
        )
    ],
    dependencies: [.package(path: "Vendor/TensorFlowLite"), .package(path: "Vendor/MediaPipeVision")],
    targets: [
        .executableTarget(name: "AppModule",
            dependencies: [.product(name: "TensorFlowLite", package: "TensorFlowLite"),
                .product(name: "MediaPipeTasksVision", package: "MediaPipeVision")],
            path: "Sources/AppModule", resources: [.copy("PoseResources")])
    ],
    swiftLanguageVersions: [.v5]
)
