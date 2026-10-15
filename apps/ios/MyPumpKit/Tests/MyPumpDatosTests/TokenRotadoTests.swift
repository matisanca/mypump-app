import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 4: la carpeta de cada cuenta va por la huella del token. Si Mati regenera el link
/// (`mypump_regenerar_token`) y el cliente pega el nuevo, la cuenta nueva arrancaba con la cola vacía y lo que quedó en
/// la vieja (las series cargadas sin señal, estacionadas con el token caído) no salía nunca. Ahora, si el token nuevo es
/// de la MISMA persona (`cliente_id`), adopta lo pendiente y los fallidos de la carpeta vieja; de otra persona, nunca.
@Suite("Lo pendiente de un link regenerado sale con el nuevo", .serialized)
@MainActor
struct TokenRotadoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("token-rotado-\(UUID().uuidString)")
    static let tokA = "AAAAAAAAAAAAAAAAAAAA"
    static let tokB = "BBBBBBBBBBBBBBBBBBBB"
    static let tokC = "CCCCCCCCCCCCCCCCCCCC"

    /// La base: cada token resuelve a su cliente mientras sea el vigente de ese cliente (regenerar reemplaza el viejo).
    func servidor(_ vigentes: Vigentes) -> Servidor {
        let s = Servidor()
        s.regla("get_cliente_info") { p in
            guard let c = vigentes.cliente(p["p_token"]?.comoTexto) else { return (200, "[]") }
            return (200, #"[{"cliente_id":"\#(c)","nombre":"Cliente","perfil":"natural"}]"#)
        }
        s.regla("get_rutina_activa") { p in vigentes.cliente(p["p_token"]?.comoTexto) == nil ? (200, "[]") : (200, "[" + filaRutina() + "]") }
        s.regla("registrar_carga") { p in vigentes.cliente(p["p_token"]?.comoTexto) == nil ? (200, "null") : (200, #""fila-1""#) }
        return s
    }

    func modelo(_ s: Servidor, _ token: String) -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(transporte: s), almacen: TokenEnMemoria(token), raizDisco: raiz)
    }

    /// Una serie con su sesión, como la deja Entreno en la cola.
    static let carga: JSONValue = .objeto([
        "sesionId": .texto("ses-1"), "diaId": .texto("d1"), "semana": .numero(5),
        "datos": .objeto(["diaId": .texto("d1"), "ejercicioId": .texto("jal-d1-0"), "ejercicioNombre": .texto("Jalón al pecho"),
                          "serie": .numero(1), "peso": .numero(60), "reps": .numero(10), "rir": .null, "notas": .null]),
    ])

    func cargasCon(_ s: Servidor, _ token: String) -> [JSONValue] {
        s.llamadas("registrar_carga").filter { $0["p_token"]?.comoTexto == token }
    }

    /// Revisión adversarial del 15-oct, hallazgo 9: un reemplazo de comida que la migración dejó solo en la carpeta del link
    /// viejo (sin la marca de migrados) se perdía al cambiar de link antes de la primera carga con red. Ahora pasa a la carpeta
    /// nueva, sin pisar lo que ya tiene, y la cola lo retiene hasta decidir; de otra persona, nunca.
    @Test func losReemplazosSinDecidirDelLinkViejoPasanAlNuevo() throws {
        let vieja = Disco(raiz: raiz, token: Self.tokA), nueva = Disco(raiz: raiz, token: Self.tokB)
        CuentasDelTelefono.anotar(clienteId: "c1", en: vieja)
        let atun = SwapLocal(original: .objeto(["name": .texto("Merluza")]), current: .objeto(["name": .texto("Atún")]))
        vieja.guardar(["swap_d_c3_0_0": atun, "swap_d_c1_0_0": SwapLocal(current: .objeto(["name": .texto("Viejo")]))], "swaps_d.json")
        nueva.guardar(["swap_d_c1_0_0": SwapLocal(current: .objeto(["name": .texto("Ricota")]))], "swaps_d.json")
        #expect(CuentasDelTelefono.adoptarSwaps(clienteId: "c1", en: nueva))
        let mapa = nueva.leer([String: SwapLocal].self, "swaps_d.json") ?? [:]
        #expect(Set(mapa.keys) == ["swap_d_c1_0_0", "swap_d_c3_0_0"])
        #expect(mapa["swap_d_c1_0_0"]?.current["name"]?.comoTexto == "Ricota", "pisó lo que la cuenta nueva ya tenía")
        #expect(ModeloApp.faltaDecidirSwaps(en: nueva), "la cola tiene que retener hasta decidir")
        #expect(vieja.leer(Bool.self, "swaps_migrados_d") == true, "la carpeta vieja tiene que quedar marcada")
        #expect(!CuentasDelTelefono.adoptarSwaps(clienteId: "c1", en: nueva), "se volvió a pasar")
        // De otra persona, nunca.
        let ajena = Disco(raiz: raiz, token: Self.tokC)
        CuentasDelTelefono.anotar(clienteId: "otra", en: ajena)
        ajena.guardar(["swap_d_c2_0_0": atun], "swaps_d.json")
        #expect(!CuentasDelTelefono.adoptarSwaps(clienteId: "c1", en: nueva))
        #expect(nueva.leer([String: SwapLocal].self, "swaps_d.json")?["swap_d_c2_0_0"] == nil)
    }

    @Test func laSerieQueQuedoConElLinkViejoSaleConElNuevo() async throws {
        let vigentes = Vigentes([Self.tokA: "c1"])
        let s = servidor(vigentes)
        let m = modelo(s, Self.tokA)
        await m.cargar()
        #expect(m.fase == .listo)

        // Mati regenera el link: A ya no vale. La serie que se carga ahora queda estacionada (token caído) en la cola de A,
        // y un fallido viejo de A (lo que la migración dejó "para revisar") también está ahí.
        vigentes.regenerar(de: Self.tokA, a: Self.tokB, cliente: "c1")
        await m.outbox?.encolar("carga", Self.carga, dedupeKey: "carga_d1_jal-d1-0_0_s5")
        let revisar = Operacion(id: "viejo-1", kind: "carga", payload: .objeto(["diaId": .texto("b2d1"), "semana": .numero(3)]),
                                dedupeKey: "carga_b2d1_x_0", ts: 1_000)
        await m.outbox?.archivarEnFallidos([revisar], motivo: "para revisar: la rutina activa ya no es la de la foto")
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 1, "con el token caído la serie queda en la cola")
        #expect(cargasCon(s, Self.tokB).isEmpty)

        // El cliente pega el link nuevo.
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.tokB)"))
        await m.outbox?.drenar()
        let enviadas = cargasCon(s, Self.tokB)
        #expect(enviadas.count == 1, "la serie de la cola vieja no salió con el link nuevo")
        #expect(enviadas.first?["p_sesion_id"]?.comoTexto == "ses-1" && enviadas.first?["p_peso"] == .numero(60))
        #expect(await m.outbox?.pendientes == 0)
        // Lo "para revisar" sigue en fallidos (no se manda, no se pierde).
        #expect(await m.outbox?.fallidos.map(\.op.id) == ["viejo-1"])
        // Entreno escribe en la cuenta nueva: el motor de la misma rutina no se queda con el token viejo.
        #expect(m.entreno?.token == Self.tokB)

        // Otro arranque con B: lo adoptado no se vuelve a adoptar ni a mandar.
        let otra = modelo(s, Self.tokB)
        await otra.cargar()
        await otra.outbox?.drenar()
        #expect(cargasCon(s, Self.tokB).count == 1, "se mandó dos veces")
        #expect(await otra.outbox?.fallidos.count == 1)
    }

    @Test func loDeOtraPersonaNoSeAdoptaNunca() async throws {
        let vigentes = Vigentes([Self.tokA: "c1"])
        let s = servidor(vigentes)
        let a = modelo(s, Self.tokA)
        await a.cargar()
        vigentes.regenerar(de: Self.tokA, a: Self.tokB, cliente: "c1")
        await a.outbox?.encolar("carga", Self.carga, dedupeKey: "carga_d1_jal-d1-0_0_s5")
        await a.outbox?.drenar()

        // En el mismo teléfono se abre el link de OTRO cliente (Mati mirando una cuenta): no se lleva nada de A.
        vigentes.agregar(Self.tokC, cliente: "c2")
        let c = modelo(s, Self.tokC)
        await c.cargar()
        await c.outbox?.drenar()
        #expect(cargasCon(s, Self.tokC).isEmpty, "mandó la serie de otra persona")
        #expect(await c.outbox?.pendientes == 0)
        #expect(await c.outbox?.fallidos.count == 0)
        // La de A sigue esperando en su carpeta, para su link nuevo.
        let b = modelo(s, Self.tokB)
        await b.cargar()
        await b.outbox?.drenar()
        #expect(cargasCon(s, Self.tokB).count == 1)
    }
}

/// Qué token vale para cada cliente (la regla del servidor corre fuera del actor principal).
final class Vigentes: @unchecked Sendable {
    private let lock = NSLock()
    private var porToken: [String: String]
    init(_ porToken: [String: String]) { self.porToken = porToken }
    func cliente(_ token: String?) -> String? { lock.withLock { token.flatMap { porToken[$0] } } }
    /// `mypump_regenerar_token`: el link viejo deja de valer y el nuevo es del mismo cliente.
    func regenerar(de viejo: String, a nuevo: String, cliente: String) {
        lock.withLock { porToken[viejo] = nil; porToken[nuevo] = cliente }
    }
    func agregar(_ token: String, cliente: String) { lock.withLock { porToken[token] = cliente } }
}
