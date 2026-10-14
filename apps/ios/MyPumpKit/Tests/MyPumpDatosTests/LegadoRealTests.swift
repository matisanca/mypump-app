import Foundation
import Testing
@testable import MyPumpDatos

/// La Fase L contra la copia de un iPhone de verdad (la del TF-0). Corre solo con `MYPUMP_LEGADO_REAL=<carpeta que
/// tiene Library/>`: la copia vive en `nativa-evidencia/privado` y nunca entra al repo. Trabaja sobre otra copia en un
/// temporal, así que el original no se toca. Muestra conteos y nunca valores (las claves de las colas llevan el token).
@Suite("Migración contra la copia de un iPhone real")
struct LegadoRealTests {
    @Test func laFaseLEncuentraTodoEnLaCopiaDelIphone() throws {
        guard let origen = ProcessInfo.processInfo.environment["MYPUMP_LEGADO_REAL"], !origen.isEmpty else { return }
        let fm = FileManager.default
        let raiz = fm.temporaryDirectory.appendingPathComponent("legado-real-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: raiz) }
        try fm.createDirectory(at: raiz, withIntermediateDirectories: true)
        let library = raiz.appendingPathComponent("Library", isDirectory: true)
        try fm.copyItem(at: URL(fileURLWithPath: origen).appendingPathComponent("Library"), to: library)
        let suite = "legado-real-\(UUID().uuidString)"
        let ajustes = try #require(UserDefaults(suiteName: suite))
        defer { ajustes.removePersistentDomain(forName: suite) }
        let almacen = TokenEnMemoria()
        let entorno = EntornoLegado(library: library, soporte: raiz.appendingPathComponent("Application Support", isDirectory: true))

        let archivos = LectorLegado.ubicar(library: library)
        #expect(!archivos.isEmpty, "no encontró el almacenamiento viejo")
        let r = try EjecutorLegado.faseLocal(entorno: entorno, almacen: almacen, ajustes: ajustes)
        #expect(r.huboLegado && r.corrio)
        #expect(r.adoptoToken, "no adoptó el token")
        #expect(almacen.leer().map(FormatoToken.valido) == true)
        let c = try #require(r.plan?.conteos)
        print("legado real: archivos \(archivos.map(\.formato.rawValue)), claves \(c.claves), ops por kind \(c.opsPorKind.sorted { $0.key < $1.key }), "
              + "colas \(c.opsPorCola.count), sin sesión \(c.opsSinSesion), ilegibles \(c.opsIlegibles)/\(c.colasIlegibles), fotos \(c.fotos) "
              + "(fuera de ventana \(c.fotosFueraDeVentana)), sustituciones \(c.sustituciones), swaps de comida \(c.swapsComida), sesiones "
              + "\(c.sesionesVigentes) vigentes y \(c.sesionesVencidas) vencidas, descanso \(c.descansoVigente), preferencias \(c.preferencias), "
              + "demo \(c.demo), ignoradas \(c.ignoradas), desconocidas \(c.desconocidas)")
        print("fase L: a la cola \(r.aLaCola), por validar \(r.porValidar), estacionadas \(r.estacionadas), anon \(r.anon), "
              + "ya en el libro \(r.yaEnElLibro), reemplazadas \(r.reemplazadas)")
    }
}
