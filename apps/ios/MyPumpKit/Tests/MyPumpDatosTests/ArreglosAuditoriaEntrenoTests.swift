import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// Auditoría del 10/11, F1: las series que ya subieron solo las conocía el servidor. Al reabrir la app sin señal se
// veían vacías y un toque en OK pisaba la buena con una cargada de memoria.

@Suite("Auditoría F1: lo ya mandado se ve al reabrir sin red", .serialized)
@MainActor
struct ArreglosAuditoriaEntrenoTests {
    @Test func serieSubidaSeVeAlReabrirSinRed() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", #""fila-1""#)
        b.servidor.cuando("set_ejercicio_estado", "true")
        let m = b.modelo()
        await m.restaurarSesion()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        await b.cola.drenar()
        #expect(await b.cola.operaciones.isEmpty, "la serie ya subió")

        // La app se cierra y se abre sin señal: el servidor no contesta nada.
        for fn in ["get_sesion_dia", "get_registros_sesion", "get_ejercicios_estado"] { b.servidor.sinRed(fn) }
        let otra = b.modelo()
        await otra.restaurarSesion()
        let s = try #require(otra.dia.ejercicios["jal-d1-0"]?.series.first)
        #expect(s.confirmada && s.kg == "60" && s.reps == "10")
        #expect(otra.seriesSinConfirmar)
    }

    @Test func conRespuestaDelServidorManda_elServidor() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", #""fila-1""#)
        let m = b.modelo()
        await m.restaurarSesion()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        await b.cola.drenar()
        // Corregida en otro lado (la web): el servidor tiene 62,5.
        b.servidor.cuando("get_registros_sesion",
                          #"[{"ejercicio_id":"jal-d1-0","serie":1,"peso_kg":62.5,"reps":10,"registrado_en":"2026-10-14T18:00:00Z"}]"#)
        let otra = b.modelo()
        await otra.restaurarSesion()
        let s = try #require(otra.dia.ejercicios["jal-d1-0"]?.series.first)
        #expect(s.kg == "62.5")
        #expect(!otra.seriesSinConfirmar)
    }

    @Test func loAnotadoViejoSePoda() {
        let viejo = ModeloEntreno.EscrituraAnotada(kind: "carga", payload: .null, ts: AHORA - 8 * 24 * 3600 * 1000)
        let nuevo = ModeloEntreno.EscrituraAnotada(kind: "carga", payload: .null, ts: AHORA - 3600 * 1000)
        let p = ModeloEntreno.podarAnotadas(["a": viejo, "b": nuevo], ahora: AHORA)
        #expect(p.keys.sorted() == ["b"])
    }
}

// Auditoría del 10/11, F5: lo que el servidor rechazaba se abandonaba en más o menos un minuto (8 intentos) con un cartel
// de 9 segundos, y no quedaba ningún lugar para reintentarlo.
@Suite("Auditoría F5: lo rechazado no se pierde", .serialized)
struct ArreglosAuditoriaColaTests {
    final class Estado: @unchecked Sendable {
        private let lock = NSLock()
        private var _ms = 1_000_000.0, _rechaza = true
        var ms: Double { get { lock.withLock { _ms } } set { lock.withLock { _ms = newValue } } }
        var rechaza: Bool { get { lock.withLock { _rechaza } } set { lock.withLock { _rechaza = newValue } } }
    }

    @Test func rechazadaSeSigueIntentandoYDespuesSeReintentaAMano() async {
        let e = Estado()
        let cola = Outbox(archivo: nil, ventanaAbandono: 30 * 60 * 1000, reintentoAutomatico: false, reloj: { e.ms }) { _ in
            e.rechaza ? .respuesta(.failure(ErrorRPC(clase: .permanente, status: 400, codigo: "22P02", mensaje: "boom")))
                      : .respuesta(.success(.texto("ok")))
        }
        _ = await cola.encolar("carga", .objeto(["x": .numero(1)]), dedupeKey: "k1")
        for _ in 0..<12 { await cola.drenar(); e.ms += 1000 }
        #expect(await cola.operaciones.count == 1, "con 12 rechazos en 12 segundos sigue en la cola")
        #expect(await cola.perdidos.isEmpty)
        e.ms += 31 * 60 * 1000
        await cola.drenar()
        #expect(await cola.operaciones.isEmpty)
        #expect(await cola.perdidos.count == 1, "pasada la ventana queda en «No se pudo guardar»")
        e.rechaza = false
        #expect(await cola.reintentarPerdidos() == 1)
        #expect(await cola.operaciones.first?.tries == 0)
        await cola.drenar()
        #expect(await cola.operaciones.isEmpty)
        #expect(await cola.perdidos.isEmpty)
    }
}

// Auditoría del 10/11, F6: una foto de progreso que el servidor rechazaba al subirse sola se borraba sin avisar.
@Suite("Auditoría F6: la foto rechazada queda a la vista", .serialized)
@MainActor
struct ArreglosAuditoriaFotosTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("fotos-rechazo-\(UUID().uuidString)")
    let token = "tokenDePrueba_0000000000"

    @Test func rechazadaEnLaColaNoSeBorraEnSilencio() async throws {
        let ok = RelojDePrueba(0)   // 0 = rechaza; 1 = acepta
        let t = TransporteProgramado { _, _ in ok.ms == 0 ? (400, #"{"ok":false,"error":"fecha fuera de rango"}"#) : (200, #"{"ok":true}"#) }
        let disco = Disco(raiz: raiz, token: token)
        let clave = "2026-11-02|frente"
        disco.guardar([clave: FotoPendiente(pose: "frente", fecha: "2026-11-03", dataUrl: "data:image/jpeg;base64,/9j/")], FotoPendiente.archivo)
        let m = ModeloFotos(cliente: ClienteRPC(transporte: t), token: token, disco: disco)
        await m.drenar()
        #expect(m.pendientes.isEmpty)
        #expect(m.rechazadas[clave]?.motivo == "fecha fuera de rango")
        // Sobrevive a cerrar la app.
        #expect(ModeloFotos(cliente: ClienteRPC(transporte: t), token: token, disco: disco).rechazadas[clave] != nil)
        ok.ms = 1
        await m.reintentarRechazada(clave)
        #expect(m.rechazadas.isEmpty && m.pendientes.isEmpty)
        #expect(t.llamadas.filter { $0 == "upload" }.count == 2)
    }
}
