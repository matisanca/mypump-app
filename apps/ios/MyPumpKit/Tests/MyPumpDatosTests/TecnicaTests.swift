import Foundation
import Testing
import AVFoundation
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola y el recorrido contra el doble que sigue el contrato. Gemelo de TecnicaTest.kt.
@MainActor
struct TecnicaTests {
    private let token = "tk-prueba-tecnica"
    /// Las esperas cortas, nada; la pasada de fondo (60 s) queda dormida: si no, se cruza con lo que prueba cada caso.
    private let espera: @Sendable (TimeInterval) async -> Void = { s in if s >= 60 { try? await Task.sleep(for: .seconds(120)) } }

    private func armar(_ d: DobleTecnica, raiz: URL? = nil) -> (ModeloTecnica, URL) {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ModeloTecnica(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token), esperar: espera), r)
    }
    private func video(_ bytes: Int = 2048) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("v-\(UUID().uuidString).mp4")
        try! Data(repeating: 7, count: bytes).write(to: u)
        return u
    }
    private func lista(_ m: ModeloTecnica) async -> ModeloTecnica {
        await m.refrescar()
        m.aceptarAviso()
        return m
    }
    private func videosEnDisco(_ m: ModeloTecnica) -> Int {
        guard let d = m.disco else { return 0 }
        return ((try? FileManager.default.contentsOfDirectory(atPath: d.url(PendienteTecnica.carpeta).path)) ?? []).count
    }

    @Test func recorridoCompleto() async {
        let d = DobleTecnica.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.habilitado)
        #expect(m.necesitaAviso)
        let sinAviso = video()
        #expect(m.encolar(archivo: sinAviso, slug: "s", nombre: "Remo", nota: "") == .ocupado)   // el aviso va primero
        m.aceptarAviso()
        #expect(!m.necesitaAviso)
        #expect(m.encolar(archivo: sinAviso, slug: "s", nombre: "Remo", nota: String(repeating: "x", count: 400)) == .guardado)
        #expect(videosEnDisco(m) == 1)
        #expect(!m.puedeMandar)
        await m.drenar()
        #expect(m.pendiente == nil)
        #expect(videosEnDisco(m) == 0)
        #expect(d.ultimoNuevo?["p_consentimiento"]?.comoTexto == Tecnica.consentimientoVigente)
        #expect(d.ultimoNuevo?["p_nota"]?.comoTexto?.count == 300)
        #expect(d.bytesSubidos == [2048])
        #expect(d.cabecerasUltimaSubida["x-tecnica-token"] == token)
        #expect(d.cabecerasUltimaSubida["Content-Length"] == "2048")
        #expect(m.envios.first?.estado == .enviado)
        #expect(!m.puedeMandar)
        #expect(m.estado?.consentimientoAceptado == true)
    }

    @Test func palancaApagadaOSinServidorNoSeVeNada() async {
        let d = DobleTecnica.escenario("sinServidor")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(!m.habilitado)
        let h = DobleTecnica.escenario("vacio"); h.habilitado = false
        let (m2, _) = armar(h)
        await m2.refrescar()
        #expect(!m2.habilitado)
        #expect(m2.encolar(archivo: video(), slug: "", nombre: "x", nota: "") == .ocupado)
        await m2.drenar()
        #expect(h.intentosDeSubida == 0)
    }

    @Test func modeloAppConPalancaApagadaNoLlamaANadaDeTecnica() async {
        let d = DobleTecnica.escenario("apagado")
        let p = PalancaRemota(.objeto(["tecnica_video": .bool(false)]))
        #expect(!p.tecnicaVideo)
        let de = PalancaRemota(.objeto([:]))
        #expect(!de.tecnicaVideo)
        #expect(d.llamadasTecnica.isEmpty)
    }

    @Test func corteDeRedASiguienteDrenajeNoPierdeNiDuplica() async {
        let d = DobleTecnica.escenario("corte")
        let (m, r) = armar(d)
        _ = await lista(m)
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.pendiente?.envioId != nil)
        #expect(videosEnDisco(m) == 1)
        // Se cerró la app: otro modelo, la misma carpeta.
        let (m2, _) = armar(d, raiz: r)
        await m2.refrescar()
        #expect(m2.pendiente?.envioId == m.pendiente?.envioId)
        await m2.drenar()
        #expect(m2.pendiente == nil)
        #expect(d.envios.count == 1)
        #expect(d.envios[0]["estado"]?.comoTexto == "enviado")
    }

    @Test func corteDespuesDeAbrirNoDuplicaElEnvio() async {
        let d = DobleTecnica.escenario("vacio"); d.consentimientoAceptado = true; d.cortesEnNuevo = 1
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.pendiente?.envioId == nil)
        await m.drenar()
        #expect(m.pendiente == nil)
        #expect(d.envios.count == 1)
    }

    @Test func errorDelServidorNoGastaElVideo() async {
        let d = DobleTecnica.escenario("reintento")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(d.intentosDeSubida == 3)
        #expect(m.pendiente == nil)
        #expect(m.aviso == nil)
    }

    @Test func insistirSinParar() async {
        let d = DobleTecnica.escenario("vacio"); d.consentimientoAceptado = true; d.proximasSubidas = [503, 503, 503]
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(d.intentosDeSubida == 3)
        #expect(m.pendiente != nil)
        #expect(videosEnDisco(m) == 1)
    }

    @Test func rechazoDefinitivoSeAvisaYSaleElVideo() async {
        let d = DobleTecnica.escenario("rechazo")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.aviso == .rechazo(.corto))
        #expect(m.pendiente == nil)
        #expect(videosEnDisco(m) == 0)
        #expect(d.llamadasTecnica.contains("mypump_tecnica_cancelar"))
        #expect(d.envios.isEmpty)
        #expect(m.puedeMandar)
    }

    @Test func tokenCaidoGuardaElVideo() async {
        let d = DobleTecnica.escenario("vacio"); d.consentimientoAceptado = true; d.proximasSubidas = [403]
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.pendiente != nil)
        #expect(videosEnDisco(m) == 1)
        #expect(d.intentosDeSubida == 1)
    }

    @Test func enCursoYTopeSeAvisan() async {
        let d = DobleTecnica.escenario("tope")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.aviso == .topeSemanal)
        #expect(m.pendiente == nil)
        let e = DobleTecnica.escenario("enRevision")
        let (m2, _) = armar(e)
        await m2.refrescar()
        #expect(!m2.puedeMandar)
        #expect(m2.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .ocupado)
    }

    @Test func cancelarBorraLocalYServidor() async {
        let d = DobleTecnica.escenario("corte")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        #expect(m.pendiente?.envioId != nil)
        #expect(await m.cancelarPendiente())
        #expect(m.pendiente == nil)
        #expect(videosEnDisco(m) == 0)
        #expect(d.envios.isEmpty)
    }

    @Test func borradorNoSeMuestra() async {
        let d = DobleTecnica.escenario("corte")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        await m.refrescar()
        #expect(m.envios.isEmpty)
    }

    @Test func publicadoSeLeeSinRed() async {
        let d = DobleTecnica.escenario("publicado")
        let (m, r) = armar(d)
        await m.refrescar()
        let dev = m.envios.first?.devolucion
        #expect(dev?.correcciones.first?.momentoS == 3.5)
        #expect(dev?.credito == "Lo revisó Mati")
        #expect(m.puedeMandar)
        d.sinRed = true
        let (m2, _) = armar(d, raiz: r)
        await m2.refrescar()
        #expect(m2.envios.first?.devolucion == dev)
    }

    @Test func sacarVideoYUrl() async {
        let d = DobleTecnica.escenario("publicado")
        let (m, _) = armar(d)
        await m.refrescar()
        let id = m.envios[0].id
        #expect(await m.urlVideo(id: id) != nil)
        #expect(await m.sacarVideo(id: id) == .ok)
        #expect(m.envios[0].tieneVideo == false)
        d.sinRed = true
        #expect(await m.sacarVideo(id: id) == .sinSenal)
    }

    @Test func archivoQueDesaparecioNoTraba() async {
        let d = DobleTecnica.escenario("corte")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await m.drenar()
        try? FileManager.default.removeItem(at: m.url(m.pendiente!.id))
        await m.drenar()
        #expect(m.pendiente == nil)
        #expect(m.aviso == .error)
    }

    @Test func huerfanosSeBarren() async {
        let d = DobleTecnica.escenario("vacio")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disco = Disco(raiz: r, token: token)
        let c = disco.url(PendienteTecnica.carpeta)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        try? Data([1]).write(to: c.appendingPathComponent("suelto.mp4"))
        let (m, _) = armar(d, raiz: r)
        #expect(videosEnDisco(m) == 0)
    }

    @Test func adoptaDeOtroLink() async {
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = DobleTecnica.escenario("corte")
        let viejo = Disco(raiz: raiz, token: "tk-viejo")
        let mv = ModeloTecnica(cliente: ClienteRPC(transporte: d), token: "tk-viejo", disco: viejo, esperar: espera)
        await mv.refrescar()
        #expect(mv.encolar(archivo: video(), slug: "s", nombre: "Remo", nota: "") == .guardado)
        await mv.drenar()
        CuentasDelTelefono.anotar(clienteId: "cli", en: viejo)
        let nuevo = Disco(raiz: raiz, token: "tk-nuevo")
        let mn = ModeloTecnica(cliente: ClienteRPC(transporte: d), token: "tk-nuevo", disco: nuevo, esperar: espera)
        #expect(CuentasDelTelefono.adoptarTecnica(clienteId: "cli", en: nuevo, tecnica: mn))
        await mn.refrescar()
        await mn.drenar()
        #expect(mn.pendiente == nil)
        #expect(d.envios.count == 1)
        #expect(d.envios[0]["estado"]?.comoTexto == "enviado")
    }

    // MARK: Compresor (un video de verdad, sintético, generado con ffmpeg)

    private func fixture() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("shared/vectores/video-prueba.mp4")
    }

    @Test func compresorSacaElAudioYDejaSoloVideo() async throws {
        let r = await CompresorVideo.preparar(entrada: fixture(), topes: TopesTecnica())
        guard case .listo(let l) = r else { Issue.record("\(r)"); return }
        defer { try? FileManager.default.removeItem(at: l.archivo) }
        let a = AVURLAsset(url: l.archivo)
        #expect(abs(l.duracion - 5) < 0.5)
        #expect(l.bytes > 0)
        #expect((try await a.loadTracks(withMediaType: .audio)).isEmpty)
        #expect((try await a.loadTracks(withMediaType: .video)).count == 1)
    }

    @Test func compresorFrenaLoQueNoEntra() async {
        var t = TopesTecnica(); t.duracionMinS = 10
        #expect(await CompresorVideo.preparar(entrada: fixture(), topes: t) == .rechazado(.corto))
        var t2 = TopesTecnica(); t2.duracionMaxS = 2
        #expect(await CompresorVideo.preparar(entrada: fixture(), topes: t2) == .rechazado(.largo))
        var t3 = TopesTecnica(); t3.bytesMax = 10
        #expect(await CompresorVideo.preparar(entrada: fixture(), topes: t3) == .rechazado(.pesado))
        let basura = FileManager.default.temporaryDirectory.appendingPathComponent("basura.mp4")
        try? Data(repeating: 1, count: 1000).write(to: basura)
        #expect(await CompresorVideo.preparar(entrada: basura, topes: TopesTecnica()) == .rechazado(.ilegible))
    }
}
