import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola de las fotos de inicio contra el doble que sigue el contrato (sección 13). Gemelas de las de Android.
@MainActor
struct FotosInicioTests {
    private let token = "tk-prueba-fotos-inicio"
    private let cuando = Date(timeIntervalSince1970: 1_794_313_800)   // 2026-11-10 09:30 en -03:00
    private let medida = FotosInicio.Medida(brillo: 120.5, nitidez: 60.25)
    private func jpeg(_ ancho: Int = 1200, _ alto: Int = 1600) -> Data { DobleFotosInicio.jpegDePrueba(ancho: ancho, alto: alto) }
    private func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func armar(_ d: DobleFotosInicio, _ r: URL? = nil, token t: String? = nil, ahora: @escaping @Sendable () -> Date = { Date() }) -> ModeloFotosInicio {
        ModeloFotosInicio(cliente: ClienteRPC(transporte: d), token: t ?? token, disco: Disco(raiz: r ?? raiz(), token: t ?? token), esperar: { _ in }, ahora: ahora)
    }
    @discardableResult private func poner(_ m: ModeloFotosInicio, _ pose: String, _ bytes: Data? = nil) -> ModeloFotosInicio.Foto {
        m.encolar(pose: pose, jpeg: bytes ?? jpeg(), tomadaEn: cuando, medida: medida)
    }
    private func existe(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
    private func gets(_ d: DobleFotosInicio) -> Int { d.llamadas.filter { $0 == "mypump_fotos_inicio_get" }.count }

    @Test func subidaFelizDeLasTresPosesYCompleto() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        #expect(m.visible)
        #expect(m.faltan == ["frente", "perfil", "espalda"])
        #expect(m.estadoPose("frente") == .falta)
        for p in ["frente", "perfil", "espalda"] { #expect(poner(m, p) == .guardada) }
        #expect(m.hechas == 3)
        #expect(!m.listas)
        #expect(m.estadoPose("perfil") == .esperando)
        let archivos = m.cola.map { m.archivo($0.id) }
        #expect(archivos.allSatisfy(existe))
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(!archivos.contains(where: existe), "los JPEG subidos se borran del teléfono")
        #expect(d.fotos.map(\.pose) == ["frente", "perfil", "espalda"])
        #expect(d.fotos[0].ancho == 1200 && d.fotos[0].alto == 1600)
        #expect(m.estado?.completo == true, "con la cola vacía se refresca y el servidor dice completo")
        #expect(m.listas)
        #expect(m.estadoPose("espalda") == .lista)
        #expect(gets(d) == 2)
        let h = d.cabecerasUltimaSubida
        #expect(h["Content-Type"] == "image/jpeg")
        #expect(h["x-inicio-token"] == token)
        #expect(h["x-inicio-pose"] == "espalda")
        #expect(h["x-inicio-foto"] == d.fotos[2].id)
        #expect(ISO8601DateFormatter().date(from: h["x-inicio-tomada"] ?? "") == cuando)
        #expect(ModeloFotosInicio.iso(cuando, zona: TimeZone(secondsFromGMT: -3 * 3600)!) == "2026-11-10T09:30:00-03:00")
        #expect(h["x-inicio-brillo"] == "120.50")
        #expect(h["x-inicio-nitidez"] == "60.25")
        #expect(d.fotos[0].bytes == jpeg())
        #expect(Set(d.fotos.map(\.id)).count == 3)
        #expect(d.fotos.allSatisfy { $0.id == $0.id.lowercased() && UUID(uuidString: $0.id) != nil })
    }

    @Test func unaPoseNuevaReemplazaALaDeLaCola() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        d.sinRed = true
        poner(m, "frente"); poner(m, "perfil")
        let vieja = m.cola.first { $0.pose == "frente" }!
        poner(m, "frente")
        #expect(m.cola.count == 2)
        #expect(!existe(m.archivo(vieja.id)), "la reemplazada se borra del disco")
        let nueva = m.cola.first { $0.pose == "frente" }!
        #expect(vieja.id != nueva.id)
        #expect(m.cola.map(\.pose) == ["perfil", "frente"])
        d.sinRed = false
        await m.drenar()
        #expect(d.dePose("frente").map(\.id) == [nueva.id])
        #expect(d.intentosDeSubida == 2, "la reemplazada nunca se intentó subir")
        poner(m, FotosInicio.motivacion, jpeg(400, 500)); poner(m, FotosInicio.motivacion, jpeg(400, 500))
        #expect(m.cola.count == 2)
    }

    @Test func unaPoseNuevaReemplazaALaDelServidorSinEsperarlo() async {
        let d = DobleFotosInicio.escenario("dos")
        let r = raiz()
        let m = armar(d, r)
        await m.refrescar()
        let viejoFrente = m.estado!.foto(pose: "frente")!.id
        let viejoPerfil = m.estado!.foto(pose: "perfil")!.id
        #expect(m.faltan == ["espalda"])
        poner(m, "frente"); poner(m, "perfil")
        let nuevoFrente = m.cola[0].id
        d.proximasSubidas = [200, 0]
        await m.drenar()
        #expect(gets(d) == 1)
        #expect(m.estado?.foto(pose: "frente")?.id == nuevoFrente, "el estado ya muestra la nueva")
        #expect(m.estado?.fotos.filter { $0.pose == "frente" }.count == 1)
        #expect(m.estado?.foto(pose: "perfil")?.id == viejoPerfil)
        #expect(m.estadoPose("perfil") == .esperando)
        #expect(d.dePose("frente").map(\.id) == [nuevoFrente])
        #expect(viejoFrente != nuevoFrente)
        d.sinRed = true
        let m2 = armar(d, r)
        await m2.refrescar()
        #expect(m2.estado?.foto(pose: "frente")?.id == nuevoFrente)
    }

    @Test func sinRedQuedaEnDiscoYReanuda() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let m = armar(d, r)
        await m.refrescar()
        d.sinRed = true
        poner(m, "frente"); poner(m, FotosInicio.motivacion, jpeg(400, 600))
        await m.drenar()
        #expect(m.cola.count == 2)
        #expect(m.estadoPose("frente") == .esperando)
        #expect(m.motivacion.count == 1 && m.motivacion[0].esperando)
        let viva = m.archivo(m.cola[0].id)
        let huerfana = viva.deletingLastPathComponent().appendingPathComponent("huerfana.jpg")
        try? jpeg().write(to: huerfana)
        let m2 = armar(d, r)
        #expect(!existe(huerfana), "se barren los JPEG que no están en el índice")
        #expect(existe(viva))
        #expect(m2.cola == m.cola)
        await m2.refrescar()
        #expect(m2.estado != nil, "sin red, lo último que se supo")
        d.sinRed = false
        await m2.drenar()
        #expect(m2.cola.isEmpty)
        #expect(d.fotos.map(\.pose) == ["frente", FotosInicio.motivacion])
    }

    @Test func sinRedYSinNadaGuardadoNoSeMuestra() async {
        let d = DobleFotosInicio.escenario("vacio")
        d.sinRed = true
        let m = armar(d)
        await m.refrescar()
        #expect(m.estado == nil)
        #expect(poner(m, "frente") == .noSeGuardo)
    }

    @Test func cincoXXNoPierdeLaFotoYSeReintenta() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        poner(m, "frente")
        d.proximasSubidas = [503, 429, 502, 200]
        await m.drenar()
        // El reintento de fondo (sin espera en las pruebas) puede haberla subido ya: lo que importa es que no se perdió.
        await esperar { d.fotos.count == 1 || d.intentosDeSubida == 3 }
        #expect(d.intentosDeSubida >= 3)
        await m.drenar()
        #expect(await esperar { m.cola.isEmpty })
        #expect(d.fotos.count == 1)
        #expect(d.intentosDeSubida == 4)
        #expect(m.aviso == nil)
    }

    @Test func cuatroXXDescartaConAvisoYSigue() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        poner(m, "frente"); poner(m, "perfil")
        d.proximasSubidas = [422]
        await m.drenar()
        #expect(m.aviso == .rechazada)
        #expect(m.cola.isEmpty)
        #expect(d.fotos.map(\.pose) == ["perfil"])
        #expect(m.estadoPose("frente") == .falta)
        poner(m, "frente", Data([1, 2, 3]))
        #expect(m.aviso == nil, "una foto nueva limpia el aviso")
        await m.drenar()
        #expect(m.aviso == .rechazada)
        #expect(m.cola.isEmpty)
        m.limpiarAviso()
        #expect(m.aviso == nil)
    }

    /// Quedaron dos de la misma pose (la nueva se encoló mientras la vieja subía y la vieja falló): solo sube la última.
    @Test func laReemplazadaQueQuedoEnLaColaNoPisaALaNueva() async throws {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let disco = Disco(raiz: r, token: token)
        let vieja = PendienteFotoInicio(id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", pose: "frente", tomadaEn: "2026-11-10T09:30:00-03:00")
        let nueva = PendienteFotoInicio(id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", pose: "frente", tomadaEn: "2026-11-10T09:31:00-03:00")
        let motivacion = PendienteFotoInicio(id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", pose: FotosInicio.motivacion, tomadaEn: "2026-11-10T09:32:00-03:00")
        try FileManager.default.createDirectory(at: disco.url(PendienteFotoInicio.carpeta), withIntermediateDirectories: true)
        for p in [vieja, nueva, motivacion] { try jpeg().write(to: disco.url("\(PendienteFotoInicio.carpeta)/\(p.id).jpg")) }
        #expect(disco.guardar([vieja, motivacion, nueva], PendienteFotoInicio.archivo))
        let m = armar(d, r)
        await m.refrescar()
        d.proximasSubidas = [503]   // aunque la primera pasada falle, la vieja no vuelve
        await m.drenar()
        #expect(await esperar { m.cola.isEmpty })
        #expect(d.dePose("frente").map(\.id) == [nueva.id])
        #expect(d.dePose(FotosInicio.motivacion).count == 1)
        #expect(!existe(m.archivo(vieja.id)))
        #expect(!d.fotos.contains { $0.id == vieja.id })
    }

    @Test func cuatroCeroTresDescartaYRefresca() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        poner(m, "frente"); poner(m, "perfil")
        d.habilitado = false   // Mati cerró la sección
        await m.drenar()
        #expect(d.fotos.isEmpty)
        #expect(d.intentosDeSubida == 1, "con 403 no se sigue probando con las demás")
        #expect(gets(d) == 2)
        #expect(m.estado == nil, "se refrescó: ya no está habilitado")
        #expect(m.aviso == nil)
        #expect(m.cola.count == 2, "con 403 las fotos no se borran: si fue el link, salen con el nuevo")
    }

    @Test func siLaCierranMientrasSubeLaQueEntroCuenta() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        poner(m, "frente"); poner(m, "perfil")
        d.cerrarAlSubir = true
        await m.drenar()
        #expect(d.fotos.map(\.pose) == ["frente"])
        #expect(m.estado == nil)
        #expect(m.cola.map(\.pose) == ["perfil"])
    }

    @Test func topeDeMotivacion() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        for _ in 0..<4 { #expect(poner(m, FotosInicio.motivacion, jpeg(400, 500)) == .guardada) }
        #expect(!m.puedeAgregarMotivacion)
        #expect(poner(m, FotosInicio.motivacion, jpeg(400, 500)) == .tope)
        #expect(m.aviso == .tope)
        await m.drenar()
        #expect(d.dePose(FotosInicio.motivacion).count == 4)
        #expect(m.motivacion.count == 4)
        #expect(!m.puedeAgregarMotivacion)
        let d2 = DobleFotosInicio.escenario("vacio"); d2.maxMotivacion = 1
        let m2 = armar(d2)
        await m2.refrescar()
        #expect(m2.maxMotivacion == 1)
        poner(m2, FotosInicio.motivacion, jpeg(400, 500))
        #expect(poner(m2, FotosInicio.motivacion, jpeg(400, 500)) == .tope)
        d2.maxMotivacion = 0
        await m2.drenar()
        #expect(m2.aviso == .tope)
        #expect(d2.fotos.isEmpty)
    }

    @Test func borrarMotivacionEnColaYEnElServidor() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        poner(m, FotosInicio.motivacion, jpeg(400, 500))
        let enCola = m.cola[0]
        #expect(await m.borrarMotivacion(id: enCola.id) == .ok)
        #expect(m.cola.isEmpty)
        #expect(!existe(m.archivo(enCola.id)))
        #expect(!d.llamadas.contains("inicio/borrar"), "la de la cola no llega a preguntarle al servidor")
        poner(m, FotosInicio.motivacion, jpeg(400, 500)); poner(m, "frente")
        await m.drenar()
        let id = d.dePose(FotosInicio.motivacion)[0].id
        #expect(m.motivacion.map(\.id) == [id])
        #expect(m.motivacion[0].archivoLocal == nil)
        d.sinRed = true
        #expect(await m.borrarMotivacion(id: id) == .sinSenal)
        #expect(m.motivacion.count == 1)
        d.sinRed = false
        #expect(await m.borrarMotivacion(id: id) == .ok)
        #expect(d.dePose(FotosInicio.motivacion).isEmpty)
        #expect(m.motivacion.isEmpty)
        #expect(await m.borrarMotivacion(id: d.dePose("frente")[0].id) == .error)
        #expect(d.dePose("frente").count == 1)
    }

    @Test func laNotaSinRedQuedaGuardadaYSaleConLaCola() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let m = armar(d, r)
        await m.refrescar()
        d.sinRed = true
        #expect(await m.guardarNota("  Hombros\ny cintura  ") == .sinSenal)
        #expect(m.notaPendiente == "Hombros y cintura")
        let m2 = armar(d, r)
        #expect(m2.notaPendiente == "Hombros y cintura")
        d.sinRed = false
        await m2.refrescar()
        await m2.drenar()
        #expect(d.nota == "Hombros y cintura")
        #expect(m2.notaPendiente == nil)
        #expect(m2.estado?.nota == "Hombros y cintura")
        #expect(armar(d, r).notaPendiente == nil, "el borrador se borra del disco")
        #expect(await m2.guardarNota(String(repeating: "💪", count: 320)) == .ok)
        #expect(d.nota.unicodeScalars.count == 300)
        #expect(d.notasRecibidas.last == d.nota)
    }

    @Test func laNotaConLaSeccionCerradaNoQuedaPendiente() async {
        let d = DobleFotosInicio.escenario("vacio")
        let m = armar(d)
        await m.refrescar()
        d.habilitado = false
        #expect(await m.guardarNota("algo") == .error)
        #expect(m.notaPendiente == nil)
        #expect(m.estado == nil)
    }

    @Test func tokenCaido() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let m = armar(d, r)
        await m.refrescar()
        d.sinRed = true
        _ = await m.guardarNota("la de antes")
        d.sinRed = false
        d.tokenCaido = true
        #expect(await m.guardarNota("la nota") == .tokenCaido)
        #expect(m.tokenCaido)
        #expect(m.notaPendiente == "la nota", "queda guardada para el link nuevo")
        await m.refrescar()
        #expect(m.estado == nil)
        #expect(m.tokenCaido)
        let m2 = armar(d, r)
        await m2.refrescar()
        #expect(m2.estado == nil)
    }

    @Test func sinServidorONoHabilitadoNoMuestraNada() async {
        for e in ["sinServidor", "noHabilitado"] {
            let d = DobleFotosInicio.escenario("vacio")
            let r = raiz()
            let disco = Disco(raiz: r, token: token)
            await armar(d, r).refrescar()
            #expect(existe(disco.url(ModeloFotosInicio.archivoEstado)))
            if e == "sinServidor" { d.sinFuncion = true } else { d.habilitado = false }
            let m = armar(d, r)
            await m.refrescar()
            #expect(m.estado == nil, "\(e)")
            #expect(!m.visible)
            #expect(!existe(disco.url(ModeloFotosInicio.archivoEstado)), "\(e): se olvida lo guardado")
            await m.drenar()
            #expect(d.intentosDeSubida == 0)
        }
    }

    @Test func miniaturasConCache() async {
        let d = DobleFotosInicio.escenario("dos")
        let reloj = Reloj()
        let m = armar(d, ahora: { reloj.ahora })
        await m.refrescar()
        await m.firmar()
        #expect(m.urls.count == 2)
        await m.firmar()
        #expect(d.llamadas.filter { $0 == "inicio/urls" }.count == 1, "dentro de los 50 min no se piden de nuevo")
        poner(m, "espalda")
        await m.drenar()
        await m.firmar()
        #expect(d.llamadas.filter { $0 == "inicio/urls" }.count == 2, "apareció una que no estaba")
        #expect(m.urls.count == 3)
        reloj.avanzar(51 * 60)
        await m.firmar()
        #expect(d.llamadas.filter { $0 == "inicio/urls" }.count == 3, "a los 50 min se piden de nuevo")
    }

    @Test func elLinkNuevoAdoptaLasFotosYLaNota() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let m = armar(d, r)
        await m.refrescar()
        d.sinRed = true
        poner(m, "frente")
        _ = await m.guardarNota("hombros")
        let nuevo = armar(d, r, token: "tk-otro-link")
        #expect(nuevo.adoptar(m.cola, desde: Disco(raiz: r, token: token)))
        #expect(nuevo.cola.count == 1)
        #expect(existe(nuevo.archivo(nuevo.cola[0].id)))
        #expect(nuevo.notaPendiente == "hombros")
    }

    @Test func laPalanca() {
        func p(_ s: String) -> PalancaRemota { PalancaRemota((try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null) }
        #expect(!p(#"{"fotos_inicio":false}"#).fotosInicio)
        #expect(p(#"{"fotos_inicio":true}"#).fotosInicio)
        #expect(!p(#"{"fotos_inicio":"si"}"#).fotosInicio)
        #expect(!PalancaRemota.deFabrica.fotosInicio)
    }

    /// Con la palanca apagada la app no llama nada de las fotos de inicio.
    @Test func palancaApagadaNoLlamaNadaNuevo() async {
        let d = DobleFotosInicio.escenario("apagado")
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz())
        await app.cargar()
        await app.alVolverLaRed()
        #expect(d.llamadas.contains("mypump_get_app_config"))
        #expect(d.llamadasFotosInicio.isEmpty)
        #expect(app.fotosInicio?.estado == nil)
    }

    @Test func palancaPrendidaCargaYSubeLoQueQuedo() async {
        let d = DobleFotosInicio.escenario("vacio")
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz())
        await app.cargar()
        guard let f = app.fotosInicio else { Issue.record("sin modelo"); return }
        #expect(await esperar { f.estado != nil })
        d.sinRed = true
        #expect(poner(f, "frente") == .guardada)
        await f.drenar()
        d.sinRed = false
        await app.alVolverLaRed()
        #expect(await esperar { d.fotos.count == 1 }, "al volver la red sale lo pendiente")
    }

    @discardableResult private func esperar(_ condicion: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if condicion() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condicion()
    }
}

private final class Reloj: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_000_000)
    var ahora: Date { lock.withLock { t } }
    func avanzar(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
}
