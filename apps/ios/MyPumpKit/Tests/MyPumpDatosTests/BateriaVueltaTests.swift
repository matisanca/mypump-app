import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Batería del iPhone (2.3.2, punto 1): bloquear el teléfono entre series cuenta como una vuelta a primer plano, y cada
/// una disparaba 8 a 12 pedidos en fila. Ahora lo que solo lee espera `Relectura.vuelta` entre vueltas; lo pendiente de
/// subir sale siempre, el chat abierto se consulta igual y un aviso tocado trae lo suyo sin esperar.
@Suite("Batería: la vuelta a primer plano no relee todo cada vez", .serialized)
@MainActor
struct BateriaVueltaTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("bateria-vuelta-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    final class Red: @unchecked Sendable {
        private let lock = NSLock()
        private var _sinRed = false
        var sinRed: Bool { get { lock.withLock { _sinRed } } set { lock.withLock { _sinRed = newValue } } }
    }

    func modelo(_ red: Red) -> (ModeloApp, TransporteProgramado) {
        let dieta = MarcasComidasTests.dieta
        let t = TransporteProgramado { fn, _ in
            if red.sinRed { throw URLError(.notConnectedToInternet) }
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_dieta_activa": return (200, dieta)
            case "mypump_marcar_comida": return (200, #"[{"comida_id":"almuerzo","estado":"comido","opcion_elegida":"A"}]"#)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
        return (m, t)
    }

    func marcas(_ t: TransporteProgramado) -> Int { t.llamadas.filter { $0 == "mypump_get_comidas_marcadas" }.count }
    func chat(_ t: TransporteProgramado) -> Int { t.llamadas.filter { $0 == "mypump_chat_nuevos" || $0 == "mypump_get_chat" }.count }

    @Test func laEsperaEsDeUnoAUnMinutoYMedio() {
        #expect(ModeloApp.Relectura.vuelta.cada >= 60 && ModeloApp.Relectura.vuelta.cada <= 120)
    }

    @Test func lasLecturasLivianasEsperanEntreUnaVueltaYOtra() async {
        let (m, t) = modelo(Red())
        var ahora = Date()
        m.relojRelecturas = { ahora }
        await m.cargar()
        let marcasAntes = marcas(t), chatAntes = chat(t)
        // Bloqueo y desbloqueo entre series: nada que leer.
        for _ in 0..<5 {
            ahora += 15
            await m.alVolverAPrimerPlano()
        }
        #expect(marcas(t) == marcasAntes, "dentro de la espera no se releen las marcas")
        #expect(chat(t) == chatAntes, "ni el chat cerrado")
        // Pasada la espera, sí, una vez.
        ahora += ModeloApp.Relectura.vuelta.cada
        await m.alVolverAPrimerPlano()
        await m.alVolverAPrimerPlano()
        #expect(marcas(t) == marcasAntes + 1)
        #expect(chat(t) == chatAntes + 1)
    }

    @Test func loPendienteDeSubirSaleEnCadaVuelta() async {
        let red = Red()
        let (m, t) = modelo(red)
        var ahora = Date()
        m.relojRelecturas = { ahora }
        await m.cargar()
        red.sinRed = true
        await m.marcar("almuerzo", .comido, opcion: 0)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 1)
        red.sinRed = false
        let marcasAntes = marcas(t)
        ahora += 5
        await m.alVolverAPrimerPlano()
        #expect(await m.outbox?.pendientes == 0, "la cola no espera el intervalo")
        #expect(t.llamadas.contains("mypump_marcar_comida"))
        #expect(marcas(t) == marcasAntes, "lo que solo lee sí lo espera")
    }

    @Test func conElChatAbiertoSeConsultaEnCadaVuelta() async {
        let (m, t) = modelo(Red())
        var ahora = Date()
        m.relojRelecturas = { ahora }
        await m.cargar()
        m.chat?.abierto = true
        let antes = chat(t), marcasAntes = marcas(t)
        ahora += 5
        await m.alVolverAPrimerPlano()
        #expect(chat(t) == antes + 1)
        #expect(marcas(t) == marcasAntes)
    }

    @Test func unAvisoTocadoTraeLoSuyoSinEsperar() async {
        let (m, t) = modelo(Red())
        var ahora = Date()
        m.relojRelecturas = { ahora }
        await m.cargar()
        let marcasAntes = marcas(t), chatAntes = chat(t)
        ahora += 5
        await m.alLlegarAviso(.revision)
        #expect(marcas(t) == marcasAntes + 1, "el aviso no espera el intervalo")
        // La vuelta que llega pegada al aviso ya no repite la lectura.
        await m.alVolverAPrimerPlano()
        #expect(marcas(t) == marcasAntes + 1)
        // El del chat solo consulta el chat.
        await m.alLlegarAviso(.chat)
        #expect(chat(t) == chatAntes + 2)
        #expect(marcas(t) == marcasAntes + 1)
    }

    /// Punto 6: sin red la cola no reintenta sola; al volver la red (`alVolverLaRed`) sale.
    @Test func sinRedLaColaEsperaAQueVuelvaLaRed() async {
        let red = Red()
        let (m, t) = modelo(red)
        await m.cargar()
        m.hayRed = false
        red.sinRed = true
        await m.marcar("almuerzo", .comido, opcion: 0)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 1)
        red.sinRed = false
        m.hayRed = true
        await m.alVolverLaRed()
        #expect(await m.outbox?.pendientes == 0)
        #expect(t.llamadas.contains("mypump_marcar_comida"))
    }

    @Test func enLaDemoUnAvisoNoLlamaANada() async {
        let (m, t) = modelo(Red())
        await m.alLlegarAviso(.revision)
        #expect(t.llamadas.isEmpty, "sin cuenta lista no hay qué leer")
    }
}
