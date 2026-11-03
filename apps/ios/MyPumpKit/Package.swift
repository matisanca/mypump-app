// swift-tools-version: 6.0
import PackageDescription

// MyPumpKit: lo que no es pantalla. Los módulos puros (sin UIKit ni HealthKit) compilan también en macOS,
// así `swift test` corre sin simulador. MyPumpReloj (tanda 3, 2.2) es lo que comparten el iPhone y el Apple Watch: el
// protocolo de mensajes, la cola del reloj y la sesión del reloj; con Modelos y Reglas compila también en watchOS
// (producto MyPumpKitReloj, el único que enlaza el reloj).
let package = Package(
    name: "MyPumpKit",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(name: "MyPumpKit", targets: ["MyPumpModelos", "MyPumpReglas", "MyPumpDatos", "MyPumpReloj"]),
        .library(name: "MyPumpKitReloj", targets: ["MyPumpModelos", "MyPumpReglas", "MyPumpReloj"]),
    ],
    targets: [
        .target(name: "MyPumpModelos"),
        .target(name: "MyPumpReglas", dependencies: ["MyPumpModelos"]),
        .target(name: "MyPumpReloj", dependencies: ["MyPumpModelos", "MyPumpReglas"]),
        .target(name: "MyPumpDatos", dependencies: ["MyPumpModelos", "MyPumpReglas", "MyPumpReloj"]),
        .testTarget(name: "MyPumpModelosTests", dependencies: ["MyPumpModelos"]),
        .testTarget(name: "MyPumpReglasTests", dependencies: ["MyPumpReglas", "MyPumpModelos"]),
        .testTarget(name: "MyPumpDatosTests", dependencies: ["MyPumpDatos", "MyPumpModelos", "MyPumpReloj"]),
        .testTarget(name: "MyPumpRelojTests", dependencies: ["MyPumpReloj", "MyPumpReglas", "MyPumpModelos"]),
    ]
)
