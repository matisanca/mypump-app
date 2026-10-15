import XCTest

/// La auditoría de accesibilidad de Xcode (contraste, zonas tocables, descripciones, texto cortado, Dynamic Type) en
/// cada pantalla, con una cuenta de prueba. No falla: junta lo que encuentra en un adjunto («auditoria-<pantalla>») para
/// revisarlo a mano, porque la auditoría también marca cosas del sistema. Corre solo con `TEST_RUNNER_MYPUMP_AUDITORIA=1`:
/// `TEST_RUNNER_MYPUMP_AUDITORIA=1 scripts/nativa/probar-ui.sh <udid> real -only-testing:MyPumpUITests/AuditoriaAccesibilidadUITests`
@MainActor
final class AuditoriaAccesibilidadUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = true
        guard ProcessInfo.processInfo.environment["MYPUMP_AUDITORIA"] == "1" else { throw XCTSkip("es una auditoría para mirar: TEST_RUNNER_MYPUMP_AUDITORIA=1") }
        guard let token = ProcessInfo.processInfo.environment["MYPUMP_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Falta MYPUMP_TOKEN: usa una cuenta de prueba, nunca un cliente.")
        }
        app.launchArguments = ["-token", token, "-sinOnboarding", "YES"]
    }

    private func auditar(_ nombre: String, pasos: Int = 4) throws {
        sleep(5)
        var hallazgos: [String] = []
        for paso in 0...pasos {
            if paso > 0 { app.swipeUp(velocity: .slow); sleep(1) }
            try app.performAccessibilityAudit { problema in
                let elemento = problema.element.map { "\($0.elementType.rawValue) «\($0.label)» \($0.identifier)" } ?? "—"
                hallazgos.append("[\(paso)] \(problema.auditType.rawValue) \(problema.compactDescription) · \(elemento)")
                return true
            }
        }
        let unicos = hallazgos.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let a = XCTAttachment(string: unicos.isEmpty ? "sin hallazgos" : unicos.joined(separator: "\n"))
        a.name = "auditoria-\(nombre)"; a.lifetime = .keepAlways; add(a)
    }

    private func abrir(_ args: [String]) { app.launchArguments += args; app.launch() }

    func testEntreno() throws { abrir(["-pestana", "entreno"]); try auditar("entreno", pasos: 8) }
    func testEjercicio() throws { abrir(["-pestana", "entreno", "-abrir", "ejercicio"]); try auditar("ejercicio", pasos: 6) }
    func testDieta() throws { abrir(["-pestana", "dieta"]); try auditar("dieta", pasos: 8) }
    func testChat() throws { abrir(["-pestana", "chat"]); try auditar("chat", pasos: 0) }
    func testRevision() throws { abrir(["-pestana", "revision"]); try auditar("revision", pasos: 8) }
    func testMisDatos() throws { abrir(["-pestana", "revision", "-abrir", "misdatos"]); try auditar("misdatos", pasos: 6) }
    func testProgreso() throws { abrir(["-pestana", "progreso"]); try auditar("progreso", pasos: 6) }
}
