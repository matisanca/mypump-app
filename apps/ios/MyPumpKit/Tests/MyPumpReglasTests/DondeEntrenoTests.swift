import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// «Mi gimnasio y mi técnica» (simplificar): títulos según lo que haya y la respuesta de técnica «nueva» del renglón.
struct DondeEntrenoTests {
    private func envio(_ id: String, _ estado: String, publicado: String?) -> EnvioTecnica? {
        var o: [String: JSONValue] = ["id": .texto(id), "estado": .texto(estado), "ejercicio_nombre": .texto("Sentadilla")]
        if let publicado { o["publicado_en"] = .texto(publicado) }
        if estado == "publicado" { o["devolucion"] = .objeto(["credito": .texto("Bien")]) }
        return EnvioTecnica(.objeto(o))
    }

    @Test func tituloYBajadaSegunLoQueHay() {
        #expect(DondeEntreno.titulo(gimnasio: true, tecnica: true) == "Mi gimnasio y mi técnica")
        #expect(DondeEntreno.titulo(gimnasio: true, tecnica: false) == "Mi gimnasio")
        #expect(DondeEntreno.titulo(gimnasio: false, tecnica: true) == "Mi técnica")
        #expect(DondeEntreno.titulo(gimnasio: false, tecnica: false) == nil)
        #expect(DondeEntreno.bajada(gimnasio: false, tecnica: false) == nil)
    }

    @Test func laRespuestaMasNuevaDeLosUltimosSieteDias() {
        let ahora = ReglasGuia.instante("2026-11-11T12:00:00-03:00")!
        let envios = [
            envio("a", "publicado", publicado: "2026-11-01T10:00:00-03:00"),   // vieja
            envio("b", "publicado", publicado: "2026-11-09T10:00:00-03:00"),
            envio("c", "publicado", publicado: "2026-11-10T10:00:00-03:00"),   // la más nueva
            envio("d", "enviado", publicado: nil),
            envio("e", "publicado", publicado: nil),                          // sin fecha: no cuenta
        ].compactMap { $0 }
        #expect(DondeEntreno.respuestaReciente(envios, ahora: ahora)?.id == "c")
        #expect(DondeEntreno.respuestaReciente(envios, ahora: ahora.addingTimeInterval(8 * 86_400)) == nil)
        #expect(DondeEntreno.respuestaReciente([], ahora: ahora) == nil)
    }
}
