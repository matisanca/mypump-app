import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola de subida y el recorrido contra el doble que sigue el contrato (`estudios/CONTRATO_APP.md`).
@MainActor
struct EstudiosTests {
    private let pdf = DobleEstudios.pdfDeEjemplo
    private func jpeg(_ n: UInt8) -> Data { Data([0xFF, 0xD8, 0xFF, 0xE0, n, 2, 3]) }
    private let token = "tk-prueba"

    private func armar(_ d: DobleEstudios, raiz: URL? = nil, token: String? = nil) -> (ModeloEstudios, URL) {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let t = token ?? self.token
        let m = ModeloEstudios(cliente: ClienteRPC(transporte: d), token: t, disco: Disco(raiz: r.appendingPathComponent("soporte"), token: t),
                               cache: r.appendingPathComponent("caches"), esperar: { _ in })
        return (m, r)
    }
    private func archivosEn(_ m: ModeloEstudios, _ carpeta: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: m.cache.appendingPathComponent(carpeta).path)) ?? []
    }

    @Test func recorridoCompleto() async {
        let d = DobleEstudios.escenario("completo")
        let (m, _) = armar(d)
        #expect(!m.habilitado)
        await m.refrescar()
        #expect(m.habilitado)
        #expect(m.pendientes == 3)
        #expect(m.estado?.ordenes.count == 3)
        #expect(m.elegir(pdf) == .ok)
        #expect(m.elegir(jpeg(1)) == .ok)
        #expect(m.elegir(jpeg(2)) == .ok)
        #expect(m.borrador.count == 3)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaBorrador).count == 3)
        m.quitar(m.borrador[2].id)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaBorrador).count == 2)
        let pedido = m.estado!.pendientes[1].id
        #expect(m.enviar(pedidoId: pedido))
        #expect(m.borrador.isEmpty)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaBorrador).isEmpty)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 2)
        #expect(m.progreso == "Subiendo 1 de 2")
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(m.aviso == .recibido)
        #expect(m.progreso == nil)
        // Al quedar enviado no queda nada en el teléfono.
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).isEmpty)
        let e = d.envios.last!
        #expect(e.estado == "enviado")
        #expect(e.pedidoId == pedido)
        #expect(Set(e.archivos.values) == [pdf, jpeg(1)])
        #expect(d.ultimoEnviar?["p_archivos"] == .numero(2))
        #expect(d.cabecerasUltimaSubida["x-estudios-token"] == token)
        #expect(d.cabecerasUltimaSubida["x-estudios-envio"] == e.id)
        #expect(d.cabecerasUltimaSubida["Content-Type"] == "image/jpeg")
        #expect(d.cabecerasUltimaSubida["Content-Length"] == "7")
        #expect(d.llamadasEstudios == ["mypump_estudios_get", "mypump_estudios_envio_nuevo", "estudios/upload", "estudios/upload", "mypump_estudios_enviar", "mypump_estudios_get"])
        // El envío nuevo ya se ve como «Recibido».
        #expect(m.estado?.enviosVisibles.count == 2)
        #expect(!d.llamadas.joined().contains("cliente_id"))
    }

    @Test func apagadoSinFuncionOTokenCaidoNoMuestraNada() async {
        for caso in ["sinServidor", "noHabilitado"] {
            let (m, _) = armar(.escenario(caso))
            await m.refrescar()
            #expect(!m.habilitado, "\(caso)")
            #expect(!m.errorDeCarga)
        }
        let d = DobleEstudios.escenario("completo")
        d.tokenCaido = true
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(!m.habilitado)
    }

    @Test func sinRedConservaLoQueSeVeiaYAvisa() async {
        let d = DobleEstudios.escenario("completo")
        let (m, raiz) = armar(d)
        await m.refrescar()
        d.sinRed = true
        await m.refrescar()
        #expect(m.habilitado)
        #expect(m.errorDeCarga)
        d.sinRed = false
        await m.refrescar()
        #expect(!m.errorDeCarga)
        // El estado no se guarda en el teléfono: otra instancia sin red no sabe nada.
        d.sinRed = true
        let (m2, _) = armar(d, raiz: raiz)
        await m2.refrescar()
        #expect(!m2.habilitado)
        #expect(!m2.errorDeCarga)
        let soporte = (try? FileManager.default.subpathsOfDirectory(atPath: raiz.appendingPathComponent("soporte").path)) ?? []
        #expect(soporte.filter { $0.hasSuffix(".json") }.isEmpty)
    }

    @Test func topesAlElegir() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.elegir(Data([0x89, 0x50, 0x4E, 0x47, 1])) == .ilegible)
        #expect(m.elegir(Data()) == .ilegible)
        var grande = Data([0xFF, 0xD8, 0xFF])
        grande.append(Data(count: 20 * 1024 * 1024))
        #expect(m.elegir(grande) == .muyGrande)
        for i in 0..<20 { #expect(m.elegir(jpeg(UInt8(i))) == .ok) }
        #expect(!m.puedeAgregar)
        #expect(m.elegir(jpeg(99)) == .tope)
        #expect(m.borrador.count == 20)
        m.descartarBorrador()
        #expect(m.borrador.isEmpty)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaBorrador).isEmpty)
        #expect(!m.enviar())
    }

    @Test func corteDeRedAMitadYReanudaAlReabrir() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, raiz) = armar(d)
        await m.refrescar()
        for i in 1...3 { _ = m.elegir(jpeg(UInt8(i))) }
        #expect(m.enviar())
        d.proximasSubidas = [200, 0]
        await m.drenar()
        #expect(m.sinSenal)
        #expect(m.cola.count == 1)
        #expect(m.progreso == "Subiendo 2 de 3")
        #expect(d.envios[0].archivos.count == 1)
        #expect(d.envios[0].estado == "borrador")
        // Los tres siguen en el teléfono hasta que el envío quede enviado.
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 3)
        // Se cierra la app: otra instancia con el mismo disco retoma.
        let (m2, _) = armar(d, raiz: raiz)
        #expect(m2.cola.count == 1)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpeta).count == 3)
        // Sin el `get` de esta sesión la sección no existe: no sale nada.
        let antes = d.llamadas.count
        await m2.drenar()
        #expect(d.llamadas.count == antes)
        await m2.refrescar()
        d.sinRed = true
        await m2.drenar()
        #expect(m2.cola.count == 1)
        d.sinRed = false
        await m2.drenar()
        #expect(!m2.sinSenal)
        #expect(m2.cola.isEmpty)
        #expect(d.envios[0].archivos.count == 3)
        #expect(d.envios[0].estado == "enviado")
        #expect(m2.aviso == .recibido)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpeta).isEmpty)
        #expect(d.envios.count == 1)
    }

    @Test func cincoCeroTresNoPierdeElArchivoYSeReintenta() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximasSubidas = [503, 429, 502, 200]
        await m.drenar()   // a la tercera seguida corta la pasada
        #expect(m.cola.count == 1)
        #expect(!m.sinSenal)
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].archivos.count == 1)
        #expect(d.intentosDeSubida == 4)
        #expect(m.aviso == .recibido)
    }

    @Test func unCuatroxxSacaEseArchivoYSigue() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        for i in 1...3 { _ = m.elegir(jpeg(UInt8(i))) }
        _ = m.enviar()
        d.proximasSubidas = [200, 413]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].archivos.count == 2)
        #expect(d.envios[0].estado == "enviado")
        #expect(d.ultimoEnviar?["p_archivos"] == .numero(2))
        #expect(m.aviso == .recibidoConRechazo)
        #expect(d.intentosDeSubida == 3)
    }

    @Test func siNoQuedaNingunoElEnvioSeDescarta() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximasSubidas = [400]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(m.aviso == .rechazado)
        #expect(d.envios[0].estado == "borrador")
        #expect(!d.llamadasEstudios.contains("mypump_estudios_enviar"))
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).isEmpty)
    }

    @Test func topeDelDia() async {
        let d = DobleEstudios.escenario("topeDia")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(m.aviso == .topeDia)
        #expect(d.intentosDeSubida == 0)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).isEmpty)
    }

    @Test func faltanArchivosVuelveASubir() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(jpeg(1)); _ = m.elegir(jpeg(2))
        _ = m.enviar()
        d.proximosEnviar = ["faltan_archivos"]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].estado == "enviado")
        #expect(d.intentosDeSubida == 4)   // los dos de nuevo: el servidor contesta `ya`
        #expect(d.envios[0].archivos.count == 2)
        #expect(m.aviso == .recibido)
    }

    @Test func faltanArchivosSinFinNoGiraParaSiempre() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximosEnviar = Array(repeating: "faltan_archivos", count: 3)
        await m.drenar()
        #expect(m.cola.count == 1, "queda para más tarde, no se pierde")
        #expect(d.intentosDeSubida == 3)
    }

    @Test func tokenCaidoNoPierdeElEnvio() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.tokenCaido = true
        await m.drenar()
        #expect(m.cola.count == 1)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 1)
        #expect(m.aviso == nil)
    }

    @Test func elMismoArchivoDosVecesEntraUnaSola() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.elegir(jpeg(1)) == .ok)
        #expect(m.elegir(jpeg(1)) == .ok)
        #expect(m.elegir(jpeg(2)) == .ok)
        #expect(m.borrador.count == 2)
        _ = m.enviar()
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].estado == "enviado")
        #expect(d.ultimoEnviar?["p_archivos"] == .numero(2))
        #expect(m.aviso == .recibido)
    }

    @Test func subidaSinPermisoNoGastaLosArchivos() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        for i in 1...2 { _ = m.elegir(jpeg(UInt8(i))) }
        _ = m.enviar()
        d.proximasSubidas = [403]
        await m.drenar()
        #expect(m.cola.first?.archivos.count == 2)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 2)
        #expect(m.aviso == nil)
        await m.drenar()   // la próxima pasada sale entera
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].archivos.count == 2)
        #expect(m.aviso == .recibido)
    }

    @Test func siElServidorNoConoceElEnvioSeAbreDeNuevo() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        for i in 1...2 { _ = m.elegir(jpeg(UInt8(i))) }
        _ = m.enviar()
        d.proximasSubidas = [200, 404]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios[0].archivos.count == 2)
        #expect(d.envios[0].estado == "enviado")
        #expect(m.aviso == .recibido)
    }

    @Test func envioYaCerradoNoGiraNiGastaReintentos() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximasSubidas = [409]
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.intentosDeSubida == 1)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).isEmpty)
    }

    @Test func siLoDeshabilitanLaColaSeConserva() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.habilitado = false
        await m.drenar()
        #expect(!m.habilitado)
        #expect(m.cola.count == 1)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 1)
        d.habilitado = true
        await m.refrescar()
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios.first?.estado == "enviado")
    }

    @Test func unEnvioQueNoSalioEnDosSemanasSeBorra() async throws {
        let d = DobleEstudios.escenario("vacio")
        let (m, raiz) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        #expect(m.cola.first?.creado != nil)
        // Se envejece el índice a mano: tres semanas atrás.
        let fm = FileManager.default
        var tocado = false
        let todos = (fm.enumerator(at: raiz, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        for u in todos where u.lastPathComponent == EnvioEstudioPendiente.archivo {
            var lista = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: u)) as? [[String: Any]])
            let viejo = try #require(lista[0]["creado"] as? Double) - 21 * 86_400
            lista[0]["creado"] = viejo
            try JSONSerialization.data(withJSONObject: lista).write(to: u)
            tocado = true
        }
        #expect(tocado)
        let (m2, _) = armar(d, raiz: raiz)
        #expect(m2.cola.isEmpty)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpeta).isEmpty)
    }

    @Test func reintentarElMismoEnvioNoDuplica() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, raiz) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximosEnviar = ["x"]   // un error que no conoce: no insiste
        await m.drenar()
        #expect(m.aviso == .error)
        #expect(m.cola.isEmpty)
        // El mismo envío abierto dos veces (la respuesta se perdió): el servidor contesta `ya`.
        let (m2, _) = armar(d, raiz: raiz)
        await m2.refrescar()
        _ = m2.elegir(jpeg(1))
        _ = m2.enviar()
        d.sinRed = true
        await m2.drenar()
        d.sinRed = false
        await m2.drenar()
        #expect(d.envios.count == 2)
        #expect(d.envios[1].estado == "enviado")
    }

    @Test func seBarreLoQueQuedoSuelto() async throws {
        let d = DobleEstudios.escenario("vacio")
        let (m, raiz) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        _ = m.elegir(jpeg(1))   // una hoja de subida que quedó abierta al cerrarse la app
        let cola = m.cache.appendingPathComponent(EnvioEstudioPendiente.carpeta)
        try pdf.write(to: cola.appendingPathComponent("huerfano.pdf"))
        let ver = m.cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer)
        try FileManager.default.createDirectory(at: ver, withIntermediateDirectories: true)
        try pdf.write(to: ver.appendingPathComponent("1.pdf"))
        let (m2, _) = armar(d, raiz: raiz)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpeta).count == 1)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpetaBorrador).isEmpty)
        #expect(archivosEn(m2, EnvioEstudioPendiente.carpetaVer).isEmpty)
        #expect(m2.cola.count == 1)
    }

    @Test func losArchivosQuedanFueraDelRespaldo() async throws {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        for carpeta in [EnvioEstudioPendiente.carpetaBorrador] {
            let v = try m.cache.appendingPathComponent(carpeta).resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(v.isExcludedFromBackup == true)
        }
        _ = m.enviar()
        let v = try m.cache.appendingPathComponent(EnvioEstudioPendiente.carpeta).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(v.isExcludedFromBackup == true)
        // En Caches, no en la carpeta de datos de la cuenta.
        #expect(m.cache.path.contains("/caches/"))
        #expect(!m.cache.path.contains(token))
    }

    @Test func yaMeLoHiceYDeshacer() async {
        let d = DobleEstudios.escenario("completo")
        let (m, _) = armar(d)
        await m.refrescar()
        let p = m.estado!.pendientes[1]
        #expect(!p.hecho)
        #expect(await m.marcarHecho(pedidoId: p.id, fecha: Estudios.Dia("2026-11-09")) == .ok)
        #expect(d.ultimoHecho?["p_fecha"] == .texto("2026-11-09"))
        #expect(m.estado!.pendientes[1].hecho)
        #expect(m.estado!.pendientes[1].hechoFecha?.corta == "9/11")
        #expect(await m.marcarHecho(pedidoId: p.id, fecha: Estudios.Dia("2026-01-01")) == .fecha)
        #expect(await m.marcarHecho(pedidoId: p.id, fecha: nil) == .ok)
        #expect(d.ultimoHecho?["p_fecha"] == .null)
        #expect(!m.estado!.pendientes[1].hecho)
        d.sinRed = true
        #expect(await m.marcarHecho(pedidoId: p.id, fecha: Estudios.Dia("2026-11-09")) == .sinSenal)
    }

    @Test func verUnaOrdenBajaAUnTemporalYSeBorraAlCerrar() async {
        let d = DobleEstudios.escenario("completo")
        let (m, _) = armar(d)
        await m.refrescar()
        let orden = m.estado!.ordenes[0]
        guard case .archivos(let a) = await m.bajarParaVer(clase: "orden", id: orden.id) else { Issue.record("no abrió"); return }
        #expect(a.count == 1)
        #expect(a[0].pdf)
        #expect((try? Data(contentsOf: a[0].url)) == pdf)
        #expect(a[0].url.path.contains(EnvioEstudioPendiente.carpetaVer))
        #expect(d.urlsPedidas.last?["clase"] == .texto("orden"))
        #expect(d.urlsPedidas.last?["token"] == .texto(token))
        m.cerrarVisor()
        #expect(!FileManager.default.fileExists(atPath: a[0].url.path))
        // Vencida o sin red: error, sin archivo. Un estudio que todavía no se abre no es un error: «Recibido…».
        #expect(await m.bajarParaVer(clase: "orden", id: m.estado!.ordenes[2].id) == .error)
        #expect(await m.bajarParaVer(clase: "estudio", id: m.estado!.estudios[0].id) == .todaviaNo)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaVer).isEmpty)
        guard case .archivos = await m.bajarParaVer(clase: "estudio", id: m.estado!.estudios[1].id) else { Issue.record("no abrió el propio"); return }
        d.sinRed = true
        #expect(await m.bajarParaVer(clase: "orden", id: orden.id) == .error)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpetaVer).isEmpty)
    }

    @Test func elLinkNuevoAdoptaLosEnvios() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, raiz) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf); _ = m.elegir(jpeg(1))
        _ = m.enviar()
        d.proximasSubidas = [200, 0]
        await m.drenar()
        let (nuevo, _) = armar(d, raiz: raiz, token: "tk-otro")
        #expect(nuevo.cola.isEmpty)
        #expect(nuevo.adoptar(m.cola, desde: m.cache))
        #expect(nuevo.cola.count == 1)
        #expect(archivosEn(nuevo, EnvioEstudioPendiente.carpeta).count == 2)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).isEmpty)
        await nuevo.refrescar()
        await nuevo.drenar()
        #expect(nuevo.cola.isEmpty)
        #expect(d.envios.count == 1)
        #expect(d.envios[0].estado == "enviado")
        #expect(d.envios[0].archivos.count == 2)
    }

    // MARK: La sección apagada no llama a nada

    @Test func conLaSeccionApagadaLaColaNoSale() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        m.usarPalanca(true)
        await m.refrescar()
        for i in 1...2 { _ = m.elegir(jpeg(UInt8(i))) }
        _ = m.enviar()
        // Se apaga la palanca con el envío esperando: ni `envio_nuevo` ni subida, tampoco al abrir la pantalla o deslizar.
        m.usarPalanca(false)
        #expect(!m.habilitado)
        let antes = d.llamadas.count
        await m.drenar()
        await m.sincronizar()
        await m.reintentar()
        #expect(d.llamadas.count == antes)
        #expect(m.cola.count == 1)
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 2)
        // Vuelve a prenderse: sale.
        m.usarPalanca(true)
        await m.refrescar()
        await m.drenar()
        #expect(m.cola.isEmpty)
        #expect(d.envios.first?.estado == "enviado")
    }

    @Test func sinLeerLaPalancaEnEstaSesionNoSeLlamaANada() async {
        let d = DobleEstudios.escenario("completo")
        let (m, _) = armar(d)
        #expect(m.palanca == nil)
        await m.sincronizar()
        #expect(d.llamadas.isEmpty)
        #expect(!m.habilitado)
        m.usarPalanca(true)
        await m.sincronizar()
        #expect(m.habilitado)
        #expect(d.llamadasEstudios == ["mypump_estudios_get"])
    }

    @Test func siSeApagaEnMedioDeLaPasadaNoSaleNiUnArchivoMas() async {
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        for i in 1...3 { _ = m.elegir(jpeg(UInt8(i))) }
        _ = m.enviar()
        d.alSubir = { [weak m] in await m?.apagar() }   // mientras sube el primero
        await m.drenar()
        #expect(d.intentosDeSubida == 1)
        #expect(m.cola.first?.archivos.count == 3)
        #expect(!m.detenida)
    }

    // MARK: La cola detenida se explica

    @Test func elLinkCaidoEnLaSubidaDejaLaColaDetenidaConProbarDeNuevo() async {
        for codigo in [401, 403] {
            let d = DobleEstudios.escenario("vacio")
            let (m, _) = armar(d)
            m.usarPalanca(true)
            await m.refrescar()
            for i in 1...2 { _ = m.elegir(jpeg(UInt8(i))) }
            _ = m.enviar()
            #expect(!m.detenida)
            d.proximasSubidas = [codigo]
            await m.drenar()
            #expect(m.detenida, "\(codigo)")
            #expect(!m.sinSenal)
            #expect(!m.subiendo)
            #expect(m.aviso == nil)
            #expect(m.cola.first?.archivos.count == 2)
            // «Probar de nuevo»: `get` y otra pasada.
            await m.reintentar()
            await m.drenar()
            for _ in 0..<50 where !m.cola.isEmpty { await Task.yield() }
            #expect(m.cola.isEmpty)
            #expect(!m.detenida)
            #expect(m.aviso == .recibido)
        }
        // Sin señal no es «detenida»: sale sola cuando vuelve.
        let d = DobleEstudios.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        _ = m.elegir(pdf)
        _ = m.enviar()
        d.proximasSubidas = [0]
        await m.drenar()
        #expect(m.sinSenal)
        #expect(!m.detenida)
    }

    // MARK: Lo que no se queda en el teléfono

    @Test func cerrarSesionNoDejaNadaMedico() async {
        let d = DobleEstudios.escenario("completo")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(token), raizDisco: r)
        await app.cargar()
        let m = app.estudios!
        #expect(m.habilitado)
        d.sinRed = true
        _ = m.elegir(pdf); _ = m.elegir(jpeg(1))
        #expect(m.enviar())
        _ = m.elegir(jpeg(2))   // una hoja abierta
        let ver = m.cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer)
        try? FileManager.default.createDirectory(at: ver, withIntermediateDirectories: true)
        try? pdf.write(to: ver.appendingPathComponent("1.pdf"))
        #expect(archivosEn(m, EnvioEstudioPendiente.carpeta).count == 2)
        app.salir()
        #expect(app.estudios == nil)
        #expect(m.cola.isEmpty)
        #expect(m.borrador.isEmpty)
        for carpeta in [EnvioEstudioPendiente.carpeta, EnvioEstudioPendiente.carpetaBorrador, EnvioEstudioPendiente.carpetaVer] {
            #expect(archivosEn(m, carpeta).isEmpty, "\(carpeta)")
        }
        #expect(m.disco?.leer([EnvioEstudioPendiente].self, EnvioEstudioPendiente.archivo) == nil)
        d.sinRed = false
        let antes = d.llamadas.count
        await m.sincronizar()
        await m.drenar()
        #expect(d.llamadas.count == antes, "después de salir no se llama a nada")
    }

    @Test func alArrancarSeBarreTodoElTelefonoSinMirarLaPalanca() async throws {
        let d = DobleEstudios.escenario("vacio")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let soporte = r.appendingPathComponent("soporte"), caches = r.appendingPathComponent("caches")
        // Una cuenta de este teléfono sin sesión (otro link, cerró sesión en otra versión) con un envío sin salir.
        let (otra, _) = armar(d, raiz: r, token: "tk-otra-cuenta")
        await otra.refrescar()
        d.sinRed = true
        _ = otra.elegir(pdf)
        #expect(otra.enviar())
        _ = otra.elegir(jpeg(1))   // y una hoja que quedó abierta
        let ver = otra.cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer)
        try FileManager.default.createDirectory(at: ver, withIntermediateDirectories: true)
        try pdf.write(to: ver.appendingPathComponent("1.pdf"))
        // Archivos de una cuenta que ya no tiene carpeta.
        let sinDueno = caches.appendingPathComponent("MyPump/cuenta-sin-dueno/\(EnvioEstudioPendiente.carpeta)")
        try FileManager.default.createDirectory(at: sinDueno, withIntermediateDirectories: true)
        try pdf.write(to: sinDueno.appendingPathComponent("x.pdf"))

        ModeloEstudios.barrerTelefono(raizDisco: soporte, raizCache: caches)
        #expect(archivosEn(otra, EnvioEstudioPendiente.carpetaBorrador).isEmpty)
        #expect(archivosEn(otra, EnvioEstudioPendiente.carpetaVer).isEmpty)
        #expect(archivosEn(otra, EnvioEstudioPendiente.carpeta).count == 1, "dentro del plazo, espera a su link nuevo")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: sinDueno.path)) ?? []).isEmpty)

        // Dos semanas después, sin que nadie abra esa cuenta ni lea la palanca: se va del teléfono.
        ModeloEstudios.barrerTelefono(raizDisco: soporte, raizCache: caches, ahora: Date().addingTimeInterval(15 * 86_400))
        #expect(archivosEn(otra, EnvioEstudioPendiente.carpeta).isEmpty)
        #expect(otra.disco?.leer([EnvioEstudioPendiente].self, EnvioEstudioPendiente.archivo) == nil)
    }

    @Test func palancaApagadaSinLaClave() {
        #expect(!PalancaRemota.deFabrica.estudiosApp)
        #expect(!PalancaRemota(.objeto([:])).estudiosApp)
        #expect(!PalancaRemota(.objeto(["estudios_app": .texto("true")])).estudiosApp, "un tipo inesperado no cuenta")
        #expect(!PalancaRemota(.objeto(["estudios_app": .bool(false)])).estudiosApp)
        #expect(PalancaRemota(.objeto(["estudios_app": .bool(true)])).estudiosApp)
        #expect(!PalancaRemota.arranque(defaults: UserDefaults(suiteName: UUID().uuidString)!).estudiosApp)
    }

    /// Con la palanca apagada, sin la función o sin habilitar, la app queda como hoy: ni sección ni llamadas de más.
    @Test func palancaApagadaNoLlamaNadaNuevo() async {
        let d = DobleEstudios.escenario("apagado")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(token), raizDisco: r)
        await app.cargar()
        await app.alVolverLaRed()
        await app.alVolverAPrimerPlano()
        #expect(d.llamadas.contains("mypump_get_app_config"))
        #expect(d.llamadasEstudios.isEmpty)
        #expect(app.estudios?.habilitado == false)
    }

    @Test func palancaPrendidaLlamaSoloAlGet() async {
        for (caso, habilitado) in [("completo", true), ("sinServidor", false), ("noHabilitado", false)] {
            let d = DobleEstudios.escenario(caso)
            let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(token), raizDisco: r)
            await app.cargar()
            #expect(app.palanca.estudiosApp)
            #expect(app.estudios?.habilitado == habilitado, "\(caso)")
            #expect(Set(d.llamadasEstudios) == ["mypump_estudios_get"], "\(caso)")
        }
    }
}
