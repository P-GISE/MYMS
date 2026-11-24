// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TensorFlowLite",
    platforms: [.iOS(.v15)],
    products: [.library(name: "TensorFlowLite", type: .dynamic, targets: ["TensorFlowLite"])],
    targets: [
        .binaryTarget(name: "TensorFlowLiteC", path: "TensorFlowLiteC.xcframework"),
        .target(name: "TensorFlowLite", dependencies: ["TensorFlowLiteC"], path: "Sources/TensorFlowLite")
    ]
)
