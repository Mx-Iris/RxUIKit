// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RxUIKit",
    platforms: [.iOS(.v13), .macCatalyst(.v13), .tvOS(.v13)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RxUIKit",
            targets: ["RxUIKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ReactiveX/RxSwift",
            .upToNextMajor(from: "6.6.0")
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RxUIKit",
            dependencies: [
                .product(name: "RxSwift", package: "RxSwift"),
                .product(name: "RxCocoa", package: "RxSwift"),
            ]
        ),
        .testTarget(
            name: "RxUIKitTests",
            dependencies: ["RxUIKit"]
        ),
    ]
)
