import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Los tres errores de producción que corrige la carga simple (2.3.0). Están escritos contra la API que ya existía: fallan
/// sobre la 2.2.0 y pasan con el arreglo.
@Suite("Carga simple: errores de producción", .serialized)
@MainActor
struct CargaSimpleErroresTests {
    /// 80 kg × 10 la vez pasada, en la serie 1 y en la 2.
    func conHistorial(_ b: Banco) -> ModeloEntreno {
        let fila = { (n: Int) in #"{"clave":"\#(ClaveEjercicio.de("Jalón al pecho"))","ejercicio_id":"jal-d1-0","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":1,"serie_numero":\#(n),"notas":null,"ejercicio_nombre":"Jalón al pecho"}"# }
        b.servidor.cuando("get_historico_por_clave", "[\(fila(1)),\(fila(2))]")
        return b.modelo()
    }

    func pesosEnCola(_ b: Banco) async -> [Double] {
        await b.cola.operaciones.filter { $0.kind == "carga" }.compactMap { $0.payload["datos"]?["peso"]?.comoNumero }
    }

    @Test func subirElKiloEnLa1YTildeEnLa2GrabaElKiloNuevo() async {
        let b = Banco()
        let m = conHistorial(b)
        await m.precargarHistorial()
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "82.5")
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        await m.confirmarSerie("jal-d1-0", 1) { _ in true }
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[1].kg == "82.5", "grababa los 80 de la semana pasada")
        #expect(await pesosEnCola(b) == [82.5, 82.5])
    }

    @Test func cambiarSoloLasRepsDeLa1NoPideElKilo() async {
        let b = Banco()
        let m = conHistorial(b)
        await m.precargarHistorial()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "11")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        let s = m.dia.ejercicios["jal-d1-0"]?.series[0]
        #expect(s?.confirmada == true, "no dejaba confirmar sin escribir el kilo")
        #expect(s?.kg == "80" && s?.reps == "11")
    }

    /// Tocar una serie hecha la desmarcaba en el teléfono, pero el servidor no la borra y al recargar volvía: ahora abre la
    /// corrección y la serie sigue hecha, sin prometer un borrado que no ocurre.
    @Test func desmarcarNoPrometeUnBorradoQueNoOcurre() async {
        let b = Banco()
        let m = conHistorial(b)
        await m.precargarHistorial()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "10")
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "80")
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        await m.editarSerie("jal-d1-0", 0)
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].confirmada == true, "la desmarcaba y al recargar volvía")
    }
}
