// swift-tools-version: 6.0
import PackageDescription

// MyPumpKit: lo que no es pantalla. Los módulos puros (sin UIKit ni HealthKit) compilan también en macOS,
// así `swift test` corre sin simulador.
let package = Package(
    name: "MyPumpKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MyPumpKit", targets: ["MyPumpModelos"]),
    ],
    targets: [
        .target(name: "MyPumpModelos"),
        .testTarget(name: "MyPumpModelosTests", dependencies: ["MyPumpModelos"]),
    ]
)
