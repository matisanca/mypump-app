import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Feedback del alumno contra el doble que sigue el SQL propuesto. Gemelo de FeedbackModeloTest.kt.
@MainActor
struct FeedbackModeloTests {
    private let token = "tk-prueba-feedback"

    private func armar(_ d: DobleFeedback, raiz: URL? = nil) -> (ModeloFeedback, URL) {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ModeloFeedback(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token)), r)
    }
    private func borrador(_ intensidad: Int = 5) -> ReglasMolestia.Borrador {
        var b = ReglasMolestia.Borrador()
        b.zona = "hombro"; b.lado = "derecho"; b.desde = "hoy"; b.cuando = "al_subir"; b.tipo = "sordo"; b.intensidad = intensidad
        return b
    }

    @Test func avisarUnaMolestia() async {
        let d = DobleFeedback()
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.dueleHabilitado && m.supleHabilitado)
        #expect(m.molestia(ejercicio: "press-d1-0") == nil)
        var b = borrador()
        b.nota = "  " + String(repeating: "x", count: 600)
        #expect(await m.avisar(id: "id-1", ejercicioId: "press-d1-0", ejercicioNombre: "Press", diaId: "d1", b, version: "2.3.0") == .ok)
        #expect(m.molestia(ejercicio: "press-d1-0")?.nombreZona == "Hombro derecho")
        #expect(m.molestia(ejercicio: "press-d1-0")?.abierta == true)
        let j = d.ultimoRegistro
        #expect(j?["p_nota"]?.comoTexto?.count == 500)
        #expect(j?["p_plataforma"]?.comoTexto == "ios")
        #expect(j?["p_intensidad"]?.comoNumero == 5)
        #expect(j?["p_token"]?.comoTexto == token)
        // Corregirla no crea otra.
        var c = borrador(9); c.zona = "codo"
        #expect(await m.avisar(id: "id-2", ejercicioId: "press-d1-0", ejercicioNombre: "Press", diaId: "d1", c, version: nil) == .ok)
        #expect(m.estado?.molestias.count == 1)
        #expect(m.molestia(ejercicio: "press-d1-0")?.zona == "codo")
        #expect(d.ultimoRegistro?["p_nota"] == .null)
    }

    @Test func incompletaNoSale() async {
        let d = DobleFeedback()
        let (m, _) = armar(d)
        await m.refrescar()
        var b = borrador(); b.tipo = nil
        #expect(await m.avisar(id: "x", ejercicioId: "e", ejercicioNombre: "E", diaId: nil, b, version: nil) == .error)
        #expect(!d.llamadasFeedback.contains("mypump_molestia_registrar"))
    }

    @Test func sinSenalYTope() async {
        let d = DobleFeedback()
        let (m, _) = armar(d)
        await m.refrescar()
        d.sinRed = true
        #expect(await m.avisar(id: "x", ejercicioId: "e", ejercicioNombre: "E", diaId: nil, borrador(), version: nil) == .sinSenal)
        #expect(m.molestia(ejercicio: "e") == nil)
        d.sinRed = false; d.tope = true
        #expect(await m.avisar(id: "x", ejercicioId: "e", ejercicioNombre: "E", diaId: nil, borrador(), version: nil) == .tope)
    }

    @Test func sinServidorNoSeVeNada() async {
        let d = DobleFeedback(); d.sinFuncion = true
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.estado == nil && !m.dueleHabilitado && !m.supleHabilitado)
    }

    @Test func sinRedQuedaLoGuardado() async {
        let d = DobleFeedback.escenario("marcado")
        let (m, raiz) = armar(d)
        await m.refrescar()
        #expect(m.marcas == ["creatina monohidrato": .tomando, "omega 3": .comprado])
        d.sinRed = true
        let (otro, _) = armar(d, raiz: raiz)
        await otro.refrescar()
        #expect(otro.marcas["omega 3"] == .comprado)
        // Si después el servidor ya no tiene la función, se apaga y no queda la copia.
        d.sinRed = false; d.sinFuncion = true
        await otro.refrescar()
        #expect(otro.estado == nil)
        d.sinRed = true
        let (tercero, _) = armar(d, raiz: raiz)
        await tercero.refrescar()
        #expect(tercero.estado == nil)
    }

    @Test func marcarUnSuplemento() async {
        let d = DobleFeedback()
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(await m.marcar(nombre: "Creatina  Monohidrato", .comprado))
        #expect(m.marcas["creatina monohidrato"] == .comprado && d.marcas["creatina monohidrato"] == "comprado")
        #expect(await m.marcar(nombre: "Creatina monohidrato", .tomando))
        #expect(d.marcas == ["creatina monohidrato": "tomando"])
        // Igual a lo que ya está: no viaja.
        let antes = d.llamadasFeedback.count
        #expect(await m.marcar(nombre: "Creatina monohidrato", .tomando))
        #expect(d.llamadasFeedback.count == antes)
    }

    @Test func siFallaVuelveAComoEstaba() async {
        let d = DobleFeedback.escenario("marcado")
        let (m, _) = armar(d)
        await m.refrescar()
        d.fallaMarcar = true
        #expect(await m.marcar(nombre: "Omega 3", .loDeje) == false)
        #expect(m.marcas["omega 3"] == .comprado)
        #expect(m.marcando.isEmpty)
        // Un protector: el servidor dice que no y la marca no queda.
        #expect(await m.marcar(nombre: "Telmisartán", .tomando) == false)
        #expect(m.marcas["telmisartan"] == nil)
    }

    @Test func palancas() {
        #expect(PalancaRemota.deFabrica.meDuele == false && PalancaRemota.deFabrica.supleEstado == false)
        let p = PalancaRemota(.objeto(["me_duele": .bool(true), "suple_estado": .texto("true")]))
        #expect(p.meDuele && !p.supleEstado)
    }
}
