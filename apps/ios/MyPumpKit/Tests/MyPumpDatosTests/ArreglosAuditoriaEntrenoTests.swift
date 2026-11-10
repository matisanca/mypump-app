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
