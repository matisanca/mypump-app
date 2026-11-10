import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola y el recorrido contra el doble que sigue el contrato.
@MainActor
struct GimnasioTests {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
    private let token = "tk-prueba"

    private func armar(_ d: DobleGimnasio, raiz: URL? = nil) -> (ModeloGimnasio, URL) {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let m = ModeloGimnasio(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token), esperar: { _ in })
        return (m, r)
    }

    private func completa(_ m: ModeloGimnasio, menos: Set<String> = []) {
        for z in Gimnasio.zonas where z.clave != "otros" && !menos.contains(z.clave) { #expect(m.agregar(zona: z.clave, jpeg: jpeg) == .guardada) }
    }

    @Test func recorridoCompleto() async {
        let d = DobleGimnasio.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.tarjetaVisible)
        #expect(!m.entradaVisible)
        #expect(m.pantalla == .inicio)
        #expect(await m.empezar() == .ok)
        #expect(m.pantalla == .zonas)
        #expect(m.faltantes.count == 9)
        completa(m, menos: ["bancos"])
        m.marcarNoHay("bancos", true)
        #expect(m.faltantes.isEmpty)
        #expect(m.puedeEnviar)
        m.fijarNota(String(repeating: "x", count: 400))
        #expect(m.nota.count == 300)
        await m.enviarCarga()
        #expect(d.fotos.count == 8)
        #expect(m.cola.isEmpty)
        #expect(m.pantalla == .recibido)
        #expect(m.envio == nil)
        #expect(d.ultimoEnviar?["p_no_hay"] == .lista([.texto("bancos")]))
        #expect(d.cabecerasUltimaSubida["x-gimnasio-token"] == token)
        #expect(d.fotos[0].bytes == jpeg)
        #expect(!d.llamadas.joined().contains("cliente_id"))
    }
    @Test func volverAEditarNoPierdeLaFoto() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        d.sinRed = true
        await m.enviarCarga()
        #expect(m.envio != nil)
        m.cancelarEnvio()
        #expect(m.envio == nil)
        #expect(m.cola.count == 1)
    }

    @Test func seBarrenLosArchivosHuerfanos() async throws {
        let d = DobleGimnasio.escenario("borrador")
        let (m, raiz) = armar(d)
        await m.refrescar()
        d.sinRed = true
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        let viva = m.fotos(zona: "poleas")[0].archivoLocal!
        let huerfana = viva.deletingLastPathComponent().appendingPathComponent("huerfana.jpg")
        try jpeg.write(to: huerfana)
        _ = armar(d, raiz: raiz)
        #expect(!FileManager.default.fileExists(atPath: huerfana.path))
        #expect(FileManager.default.fileExists(atPath: viva.path))
    }

    @Test func sinRedSoloSeSigueUnaCargaAMedias() async {
        let d = DobleGimnasio.escenario("listo")
        let (m, raiz) = armar(d)
        await m.refrescar()
        d.sinRed = true
        let (m2, _) = armar(d, raiz: raiz)
        await m2.refrescar()
        #expect(m2.estado == nil)
    }

    @Test func elLinkNuevoAdoptaFotosYEnvio() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, raiz) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        d.sinRed = true
        await m.enviarCarga()
        let nuevo = ModeloGimnasio(cliente: ClienteRPC(transporte: d), token: "tk-otro", disco: Disco(raiz: raiz, token: "tk-otro"), esperar: { _ in })
        #expect(nuevo.adoptar(m.cola, desde: Disco(raiz: raiz, token: token)))
        #expect(nuevo.cola.count == 1)
        #expect(nuevo.envio != nil)
    }

    @Test func corteDeRedAMitadYReanuda() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, raiz) = armar(d)
        await m.refrescar()
        for z in ["poleas", "piernas", "empuje"] { _ = m.agregar(zona: z, jpeg: jpeg) }
        d.proximasSubidas = [200, 0]
        await m.enviarCarga()
        #expect(d.fotos.count == 1)
        #expect(m.cola.count == 2)
        #expect(m.envio != nil)
        // Se cierra la app: otra instancia, con el mismo disco, retoma cola y envío.
        let (m2, _) = armar(d, raiz: raiz)
        #expect(m2.cola.count == 2)
        #expect(m2.envio != nil)
        await m2.refrescar()
        d.sinRed = true
        await m2.drenar()
        #expect(m2.cola.count == 2)
        d.sinRed = false
        for z in ["accesorios_polea", "tiron", "barras_racks", "discos", "mancuernas", "bancos"] { m2.marcarNoHay(z, true) }
        await m2.enviarCarga()
        #expect(d.fotos.count == 3)
        #expect(m2.cola.isEmpty)
        #expect(m2.pantalla == .recibido)
    }

    @Test func cincoCeroTresNoPierdeLaFotoYSeReintenta() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        d.proximasSubidas = [503, 429, 502, 200]
        await m.drenar()   // a la tercera seguida corta la pasada
        #expect(m.cola.count == 1)
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.fotos.count == 1)
        #expect(d.intentosDeSubida == 4)
    }

    @Test func sinDuplicarAlReintentarLaMisma() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        await m.drenar()
        // El servidor ya la tiene pero la cola quedó (se cerró la app justo): vuelve con el mismo id y contesta `ya`.
        let id = d.fotos[0].id
        let (m2, _) = armar(d)
        await m2.refrescar()
        #expect(m2.fotos(zona: "poleas").map(\.id) == [id])
        #expect(d.fotos.count == 1)
    }

    @Test func fotoRechazadaAvisaYSigue() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        _ = m.agregar(zona: "piernas", jpeg: jpeg)
        d.proximasSubidas = [400]
        await m.drenar()
        #expect(m.avisoFoto == .rechazada)
        #expect(m.cola.isEmpty)
        #expect(d.fotos.map(\.zona) == ["piernas"])
    }

    @Test func topeDeOchenta() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        for _ in 0..<80 { #expect(m.agregar(zona: "otros", jpeg: jpeg) == .guardada) }
        #expect(m.agregar(zona: "otros", jpeg: jpeg) == .tope)
        #expect(m.avisoFoto == .tope)
        #expect(!m.puedeAgregar)
    }

    @Test func tercesSeDescartaYRefresca() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        d.proximasSubidas = [409]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.llamadas.filter { $0 == "mypump_gimnasio_get" }.count == 2)
    }

    @Test func faltanFotosAlEnviar() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        await m.enviarCarga()
        guard case .faltan(let f)? = m.avisoEnvio else { Issue.record("sin aviso"); return }
        #expect(f.count == 8)
        #expect(m.envio == nil)
    }

    @Test func preguntasConFotoVanDespuesDeLaFoto() async {
        let d = DobleGimnasio.escenario("preguntas")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.pantalla == .preguntas)
        let ps = m.abierta!.preguntas
        #expect(ps.count == 6)
        #expect(Gimnasio.fotosPedidas(ps, m.respuestas) == 1)
        m.responder("remo", .lista([.texto("remo_t")]))
        m.responder("peso_mancuernas", .numero(50))
        _ = m.agregar(zona: "bancos", jpeg: jpeg, pregunta: "foto_1")
        d.sinRed = true
        await m.enviarRespuestas()
        #expect(m.envio != nil)
        d.sinRed = false
        await m.drenar()
        #expect(d.fotos.count == 1)
        guard case .objeto(let r)? = d.ultimoResponder else { Issue.record("no respondió"); return }
        #expect(r["remo"] == .lista([.texto("remo_t")]))
        #expect(r["foto_1"] == .texto("subida"))
        #expect(r["peso_discos"] == nil)
        #expect(m.pantalla == .recibido)
    }

    @Test func listoYParcial() async {
        let d = DobleGimnasio.escenario("listo")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.pantalla == .listo)
        #expect(!m.tarjetaVisible)
        #expect(m.entradaVisible)
        #expect(m.vigente?.equipos.count == 4)
        #expect(await m.empezar(modo: "parcial") == .ok)
        #expect(m.abierta?.modo == "parcial")
        #expect(m.pantalla == .zonas)
        #expect(!m.puedeEnviar)
        m.alternarQuitar("prensa_45")
        #expect(m.puedeEnviar)
        await m.enviarCarga()
        #expect(d.ultimoEnviar?["p_quitar"] == .lista([.texto("prensa_45")]))
    }

    @Test func apagadoNoMuestraNada() async {
        for caso in ["sinServidor"] {
            let d = DobleGimnasio.escenario(caso)
            let (m, _) = armar(d)
            await m.refrescar()
            #expect(m.estado == nil)
            #expect(!m.tarjetaVisible)
            #expect(!m.entradaVisible)
        }
        let d = DobleGimnasio.escenario("vacio")
        d.habilitado = false
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.estado == nil)
    }

    @Test func sinRedLaPrimeraVezNoMuestraYDespuesUsaLoGuardado() async {
        let d = DobleGimnasio.escenario("borrador")
        d.sinRed = true
        let (m, raiz) = armar(d)
        await m.refrescar()
        #expect(m.estado == nil)
        d.sinRed = false
        await m.refrescar()
        #expect(m.estado != nil)
        d.sinRed = true
        let (m2, _) = armar(d, raiz: raiz)
        await m2.refrescar()
        #expect(m2.pantalla == .zonas)
    }

    @Test func borrarFotoPendienteYSubida() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        let local = m.cola[0].id
        #expect(await m.borrarFoto(id: local) == .ok)
        #expect(m.cola.isEmpty)
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        await m.drenar()
        let subida = d.fotos[0].id
        #expect(await m.borrarFoto(id: subida) == .ok)
        #expect(d.fotos.isEmpty)
        #expect(m.fotos(zona: "poleas").isEmpty)
    }

    @Test func noHaySeSacaAlSumarFoto() async {
        let d = DobleGimnasio.escenario("borrador")
        let (m, _) = armar(d)
        await m.refrescar()
        m.marcarNoHay("poleas", true)
        #expect(m.noHay == ["poleas"])
        _ = m.agregar(zona: "poleas", jpeg: jpeg)
        #expect(m.noHay.isEmpty)
    }

    /// Con la palanca apagada la app no llama nada del gimnasio.
    @Test func palancaApagadaNoLlamaNadaNuevo() async {
        let d = DobleGimnasio.escenario("apagado")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(token), raizDisco: r)
        await app.cargar()
        await app.alVolverLaRed()
        #expect(d.llamadas.contains("mypump_get_app_config") || d.llamadas.isEmpty == false)
        #expect(d.llamadasGimnasio.isEmpty)
        #expect(app.gimnasio?.estado == nil)
    }
}
