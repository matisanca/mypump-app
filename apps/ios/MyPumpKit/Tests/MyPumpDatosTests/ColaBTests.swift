import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola B de la 2.3.0 contra el servidor de mentira (`DobleColaB`): Tu recorrido, Dónde comprarlo y Entreno en casa.
@Suite("Cola B", .serialized)
@MainActor
struct ColaBTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("colab-\(UUID().uuidString)")
    static let token = "AAAAAAAAAAAAAAAAAAAA"

    func cliente(_ d: DobleColaB) -> ClienteRPC { ClienteRPC(transporte: d, espera: 2) }
    func disco() -> Disco { Disco(raiz: raiz, token: Self.token) }
    func recorrido(_ d: DobleColaB) -> ModeloRecorrido { ModeloRecorrido(cliente: cliente(d), token: Self.token, disco: disco()) }
    func compras(_ d: DobleColaB) -> ModeloCompras { ModeloCompras(cliente: cliente(d), token: Self.token, disco: disco()) }
    func casa(_ d: DobleColaB) -> ModeloCasa { ModeloCasa(cliente: cliente(d), token: Self.token, disco: disco()) }
    static func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    // MARK: Palancas

    @Test func lasPalancasNacenApagadasYSoloTrueLasPrende() {
        #expect(!PalancaRemota.deFabrica.finPlan && !PalancaRemota.deFabrica.comprasPais && !PalancaRemota.deFabrica.casa)
        let p = PalancaRemota(Self.json(#"{"fin_plan":true,"compras_pais":"true","casa":1}"#))
        #expect(p.finPlan && !p.comprasPais && !p.casa)
        let d = UserDefaults(suiteName: "colab-\(UUID().uuidString)")!
        p.recordar(defaults: d)
        let a = PalancaRemota.arranque(defaults: d)
        #expect(a.finPlan && !a.comprasPais && !a.casa)
    }

    // MARK: Tu recorrido

    @Test func recorridoPublicadoSeVeYSeAbreSolaUnaVez() async {
        let d = DobleColaB.escenario("todo")
        let m = recorrido(d)
        await m.refrescar()
        #expect(m.estado?.estado == .publicado)
        #expect(m.estado?.resumen.logros.count == 4)
        #expect(m.estado?.resumen.logros.first == LogroRecorrido(titulo: "Entrenamientos", valor: "58", detalle: "Casi no faltaste"))
        #expect(m.abrirSola)
        m.seAbrio()
        #expect(!m.abrirSola)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(d.vistos == 1)
        // Otra vuelta, y otra vez la app: ya no se abre sola.
        await m.refrescar()
        #expect(!m.abrirSola)
        let otro = recorrido(d)
        await otro.refrescar()
        #expect(!otro.abrirSola && otro.estado != nil)
        // Mati publica otro resumen: una vez más.
        d.recorridoResumen = Self.json(#"{"logros":[{"titulo":"Peso","valor":"-7 kg"}]}"#)
        await otro.refrescar()
        #expect(otro.abrirSola && otro.estado?.resumen.titulo == nil)
    }

    @Test func recorridoApagadoNoVisibleSinServidorOTokenCaidoNoSeVe() async {
        for caso in ["apagado", "noVisible", "sinServidor", "raro", "sinLogros", "estadoNuevo"] {
            let d = DobleColaB.escenario("todo")
            let m = recorrido(d)
            await m.refrescar()
            #expect(m.estado != nil, "\(caso): de partida se ve")
            switch caso {
            case "apagado": d.palancas["fin_plan"] = false
            case "noVisible": d.recorridoVisible = false
            case "sinServidor": d.sinFuncion = true
            case "raro": d.recorridoResumen = .texto("roto")
            case "sinLogros": d.recorridoResumen = Self.json(#"{"titulo":"x","logros":[{"titulo":"sin valor"}]}"#)
            default: d.recorridoEstado = "cerrado"
            }
            await m.refrescar()
            #expect(m.estado == nil && !m.abrirSola, "\(caso)")
            // Y no queda copia: otro arranque, sin red, tampoco lo muestra.
            d.sinRed = true
            let otro = recorrido(d)
            await otro.refrescar()
            #expect(otro.estado == nil, "\(caso): sin copia")
            try? FileManager.default.removeItem(at: raiz)
        }
    }

    @Test func recorridoSinRedDejaLoUltimoGuardado() async {
        let d = DobleColaB.escenario("todo")
        await recorrido(d).refrescar()
        d.sinRed = true
        let m = recorrido(d)
        #expect(m.estado == nil)
        await m.refrescar()
        #expect(m.estado?.estado == .publicado)
        // Sin copia y sin red: nada.
        try? FileManager.default.removeItem(at: raiz)
        let vacio = recorrido(d)
        await vacio.refrescar()
        #expect(vacio.estado == nil)
    }

    @Test func pedirMandaLasRespuestasSaneadasYQuedaPedido() async {
        let d = DobleColaB.escenario("todo")
        let m = recorrido(d)
        await m.refrescar()
        m.responder("mejor", "  La constancia  ")
        m.responder("costo", "   ")
        m.responder("objetivo", String(repeating: "x", count: 700))
        m.responder("otra", "no va")
        #expect(m.respuestas["objetivo"]?.count == 500 && m.respuestas["otra"] == nil)
        await m.pedir()
        #expect(m.envio == .ninguno && m.estado?.estado == .pedido)
        #expect(d.pedidos.count == 1)
        #expect(d.pedidos.first?.respuestas == .objeto(["mejor": .texto("La constancia"), "objetivo": .texto(String(repeating: "x", count: 500))]))
        #expect(UUID(uuidString: d.pedidos.first?.id ?? "") != nil)
        #expect(m.respuestas.isEmpty)
        // Pedir otra vez no hace nada: ya está pedido.
        await m.pedir()
        #expect(d.cuantas("mypump_fin_plan_pedir") == 1)
    }

    @Test func unCorteAlPedirSeReintentaConElMismoId() async throws {
        let d = DobleColaB.escenario("falla")
        let m = recorrido(d)
        await m.refrescar()
        m.responder("mejor", "Todo")
        await m.pedir()
        #expect(m.envio == .error && m.estado?.estado == .publicado && d.pedidos.isEmpty)
        #expect(m.respuestas["mejor"] == "Todo")
        // El id quedó en el disco antes de mandar: lo usa el reintento, también después de cerrar la app.
        struct B: Decodable { let pedidoId: String? }
        let guardado = try #require(disco().leer(B.self, "recorrido-borrador.json")?.pedidoId)
        let otro = recorrido(d)
        await otro.refrescar()
        #expect(otro.respuestas["mejor"] == "Todo")
        await otro.pedir()
        #expect(otro.estado?.estado == .pedido && d.pedidos.first?.id == guardado)
    }

    @Test func siYaNoCorrespondeAlPedirDesaparece() async {
        for falla in ["no_disponible", "apagado"] {
            let d = DobleColaB.escenario("todo")
            let m = recorrido(d)
            await m.refrescar()
            d.proximoPedir = falla
            await m.pedir()
            #expect(m.estado == nil && m.envio == .ninguno, "\(falla)")
            try? FileManager.default.removeItem(at: raiz)
        }
        let d = DobleColaB.escenario("todo")
        let m = recorrido(d)
        await m.refrescar()
        d.proximoPedir = "500"
        await m.pedir()
        #expect(m.estado?.estado == .publicado && m.envio == .error)
    }

    @Test func pedidoYAgendadoNoSeAbrenSolosNiSePiden() async {
        for (caso, estado) in [("pedido", EstadoRecorrido.Estado.pedido), ("agendado", .agendado)] {
            let d = DobleColaB.escenario(caso)
            let m = recorrido(d)
            await m.refrescar()
            #expect(m.estado?.estado == estado && !m.abrirSola)
            await m.pedir()
            #expect(d.cuantas("mypump_fin_plan_pedir") == 0)
            try? FileManager.default.removeItem(at: raiz)
        }
        let d = DobleColaB.escenario("agendaApp")
        let m = recorrido(d)
        await m.refrescar()
        #expect(m.estado?.agendaEnLaApp == true)
        d.agenda = "otra"
        await m.refrescar()
        #expect(m.estado?.agendaEnLaApp == false)
    }

    @Test func alTelefonoNoLeImportanCamposDeMas() {
        let e = EstadoRecorrido(Self.json(#"{"habilitado":true,"visible":true,"estado":"publicado","nuevo":{"a":1},"agenda":7,"respuestas":{"mejor":" x ","otra":"y","costo":5},"resumen":{"mensaje":"  ","logros":[{"titulo":"A","valor":"1","detalle":""},"roto",{"titulo":"B","valor":"2","extra":true},{"titulo":"C","valor":"3"},{"titulo":"D","valor":"4"},{"titulo":"E","valor":"5"},{"titulo":"F","valor":"6"},{"titulo":"G","valor":"7"}]}}"#))
        #expect(e?.resumen.logros.map(\.titulo) == ["A", "B", "C", "D", "E"])   // tope de 6 antes de filtrar
        #expect(e?.resumen.mensaje == nil && e?.resumen.logros.first?.detalle == nil)
        #expect(e?.respuestas == ["mejor": "x"] && e?.agendaEnLaApp == false)
    }

    // MARK: Dónde comprarlo

    @Test func comprasCruzaPorNombreExacto() async {
        let d = DobleColaB.escenario("todo")
        let m = compras(d)
        await m.refrescar()
        #expect(m.hay && m.items.count == 2)
        #expect(m.opciones(para: "Creatina monohidrato").map(\.tienda) == ["Tienda Ejemplo", "Farmacia de Muestra"])
        #expect(m.opciones(para: "  Creatina monohidrato ").count == 2)
        #expect(m.opciones(para: "Creatina").isEmpty && m.opciones(para: "creatina monohidrato").isEmpty && m.opciones(para: "").isEmpty)
        #expect(m.opciones(para: "Omega 3").isEmpty)
        #expect(m.opciones(para: "Creatina monohidrato").first?.url?.absoluteString == "https://tienda-ejemplo.invalid/creatina")
        #expect(m.opciones(para: "Creatina monohidrato").last?.url == nil)
    }

    @Test func unaDireccionQueNoEsHttpsNoSeAbre() {
        for mala in ["http://x.invalid", "javascript:alert(1)", "https://", "https://usuario:clave@x.invalid", "https://x.invalid/a b", " https://x.invalid", "ftp://x.invalid", "tel:123", "HTTPS://x.invalid", ""] {
            #expect(Compras.urlSegura(mala) == nil, "\(mala)")
        }
        #expect(Compras.urlSegura("https://x.invalid/p?q=1") != nil)
        #expect(Compras.urlSegura(nil) == nil)
        let items = Compras.items(Self.json(#"{"habilitado":true,"items":[{"nombre":"A","opciones":[{"producto":"P","tienda":"T","url":"http://x.invalid"},{"producto":"","tienda":"T"},{"tienda":"T"},"roto"]},{"nombre":"B","opciones":[]},{"nombre":" ","opciones":[{"producto":"P","tienda":"T"}]},{"nombre":"C","opciones":[{"producto":"1","tienda":"T"},{"producto":"2","tienda":"T"},{"producto":"3","tienda":"T"},{"producto":"4","tienda":"T"},{"producto":"5","tienda":"T"}]}]}"#))
        #expect(items.map(\.nombre) == ["A", "C"])
        #expect(items[0].opciones == [OpcionCompra(producto: "P", tienda: "T", url: nil, nota: nil)])
        #expect(items[1].opciones.count == 4)
        #expect(Compras.items(Self.json(#"{"habilitado":false,"items":[{"nombre":"A","opciones":[{"producto":"P","tienda":"T"}]}]}"#)).isEmpty)
    }

    @Test func comprasApagadaVaciaOSinServidorNoMuestraNada() async {
        for caso in ["apagado", "vacio", "sinServidor"] {
            let d = DobleColaB.escenario("todo")
            let m = compras(d)
            await m.refrescar()
            #expect(m.hay)
            switch caso {
            case "apagado": d.palancas["compras_pais"] = false
            case "vacio": d.compras = Self.json(#"{"habilitado":true,"pais":"AR","items":[]}"#)
            default: d.sinFuncion = true
            }
            await m.refrescar()
            #expect(!m.hay, "\(caso)")
            d.sinRed = true
            let otro = compras(d)
            await otro.refrescar()
            #expect(!otro.hay, "\(caso): sin copia")
            try? FileManager.default.removeItem(at: raiz)
        }
        // Sin red, lo guardado.
        let d = DobleColaB.escenario("todo")
        await compras(d).refrescar()
        d.sinRed = true
        let m = compras(d)
        await m.refrescar()
        #expect(m.items.count == 2)
    }

    // MARK: Entreno en casa

    @Test func elInterruptorAbreUnaCargaDeCasaYVuelve() async {
        let d = DobleColaB.escenario("todo")
        let m = casa(d)
        await m.refrescar()
        #expect(m.visible && !m.prendido && !m.fijo && m.pantalla == .ninguna)
        #expect(m.estado?.tipos.count == 16)
        #expect(await m.elegir(true) == .ok)
        #expect(m.prendido && m.pantalla == .lista && !m.fijo)
        #expect(d.gimnasio.abierta?["lugar"] == .texto("casa"))
        #expect(await m.elegir(false) == .ok)
        #expect(!m.prendido && m.pantalla == .ninguna)
        #expect(d.gimnasio.abierta?["lugar"] == .texto("gimnasio"))
    }

    @Test func enviarLoQueTieneEnCasa() async throws {
        let d = DobleColaB.escenario("casaBorrador")
        let m = casa(d)
        await m.refrescar()
        #expect(m.pantalla == .lista && !m.puedeEnviar)
        #expect(await m.enviar() == .sinDatos)
        m.marcar("banco_plano", true); m.marcar("mancuernas", true); m.marcar("no_existe", true)
        m.fijarKilos("mancuernas", "20,26"); m.fijarKilos("banco_plano", "50")
        m.fijarNota("  Tengo poco espacio ")
        #expect(m.marcados == ["mancuernas", "banco_plano"] && m.puedeEnviar)
        // Se cerró la app: lo marcado sigue.
        let otro = casa(d)
        await otro.refrescar()
        #expect(otro.marcados == ["mancuernas", "banco_plano"] && otro.kilos("mancuernas") == "20,26" && otro.nota == "  Tengo poco espacio ")
        #expect(await otro.enviar() == .ok)
        let j = try #require(d.ultimoEnviarCasa)
        #expect(j["p_equipos"] == Self.json(#"[{"tipo":"mancuernas","kg":20.3},{"tipo":"banco_plano"}]"#))   // orden del servidor, kilos solo donde van
        #expect(j["p_sin_equipo"] == .bool(false) && j["p_nota"] == .texto("Tengo poco espacio"))
        #expect(otro.pantalla == .recibido && otro.fijo && otro.prendido)
        #expect(otro.marcados.isEmpty)
        // Ya enviada, el interruptor no la cambia.
        #expect(await otro.elegir(false) == .enCurso)
        #expect(otro.prendido)
        d.aprobarAbierta()
        await otro.refrescar()
        #expect(otro.pantalla == .vigente && !otro.fijo && otro.prendido)
        #expect(otro.estado?.vigente?.equipos == [EquipoCasa(tipo: "mancuernas", kg: 20.3), EquipoCasa(tipo: "banco_plano")])
        #expect(otro.nombre("banco_plano") == "Banco plano")
    }

    @Test func noTengoNadaEsExcluyente() async throws {
        let d = DobleColaB.escenario("casaBorrador")
        let m = casa(d)
        await m.refrescar()
        m.marcar("discos", true); m.fijarKilos("discos", "40")
        m.marcarSinEquipo(true)
        #expect(m.marcados.isEmpty && m.sinEquipo && m.puedeEnviar && m.kilos("discos") == "")
        m.marcar("trx", true)
        #expect(!m.sinEquipo && m.marcados == ["trx"])
        m.marcarSinEquipo(true)
        #expect(await m.enviar() == .ok)
        let j = try #require(d.ultimoEnviarCasa)
        #expect(j["p_equipos"] == .lista([]) && j["p_sin_equipo"] == .bool(true) && j["p_nota"] == .null)
    }

    @Test func casaApagadaOSinMiGimnasioNoSeVe() async {
        for caso in ["casa", "gimnasio_fotos", "alumno", "sinServidor", "sinTipos"] {
            let d = DobleColaB.escenario("todo")
            let m = casa(d)
            await m.refrescar()
            #expect(m.visible)
            switch caso {
            case "alumno": d.casaHabilitada = false
            case "sinServidor": d.sinFuncion = true
            case "sinTipos": d.palancas["casa"] = true; d.gimnasio.habilitado = false
            default: d.palancas[caso] = false
            }
            await m.refrescar()
            #expect(!m.visible && !m.prendido && m.pantalla == .ninguna, "\(caso)")
        }
    }

    @Test func unCorteAlCambiarOAlEnviarNoRompeNada() async {
        let d = DobleColaB.escenario("casaBorrador")
        let m = casa(d)
        await m.refrescar()
        m.marcar("discos", true)
        d.proximoCasa = "red"
        #expect(await m.enviar() == .sinSenal)
        #expect(m.pantalla == .lista && m.marcados == ["discos"])
        d.proximoCasa = "red"
        #expect(await m.elegir(false) == .sinSenal)
        #expect(m.prendido)
        d.proximoCasa = "reintentar"
        #expect(await m.elegir(false) == .ok)
        d.proximoCasa = "no_habilitado"
        #expect(await m.elegir(true) == .error)
        #expect(!m.visible)
    }

    @Test func reglasDeCasa() {
        #expect(Casa.kilos("20") == 20 && Casa.kilos(" 12,5 ") == 12.5 && Casa.kilos("12.26") == 12.3)
        for malo in ["", "0", "0,5", "401", "abc", "-5", "1e3", "٣", "12,5,1"] { #expect(Casa.kilos(malo) == nil, "\(malo)") }
        #expect(Casa.textoKilos(20) == "hasta 20 kg" && Casa.textoKilos(12.5) == "hasta 12,5 kg")
        #expect(!Casa.puedeEnviar(marcados: [], sinEquipo: false) && Casa.puedeEnviar(marcados: [], sinEquipo: true))
        #expect(Casa.puedeEnviar(marcados: ["x"], sinEquipo: false) && !Casa.puedeEnviar(marcados: ["x"], sinEquipo: true))
        let e = EstadoCasa(Self.json(#"{"habilitado":true,"tipos":[{"tipo":"a","nombre":"A","kg":true},{"tipo":"a","nombre":"Repetido"},{"tipo":"b","nombre":" "},{"nombre":"sin tipo"},{"tipo":"c","nombre":"C","kg":"si"}],"abierta":{"id":"1","estado":"borrador","lugar":"otro","equipos":[{"tipo":"a","kg":-3},{"kg":2},"x"]},"vigente":{"id":"2","estado":"listo","lugar":"casa"}}"#))
        #expect(e?.tipos == [TipoCasa(tipo: "a", nombre: "A", kg: true), TipoCasa(tipo: "c", nombre: "C", kg: false)])
        #expect(e?.abierta?.enCasa == false && e?.abierta?.equipos == [EquipoCasa(tipo: "a")])
        #expect(!Casa.prendido(e) && Casa.pantalla(e) == .ninguna)   // manda la abierta, que es de gimnasio
        #expect(EstadoCasa(Self.json(#"{"habilitado":true,"tipos":[]}"#)) == nil && EstadoCasa(Self.json(#"{"habilitado":true}"#)) == nil)
    }

    // MARK: La app entera

    /// La cuenta y lo demás, lo mínimo; lo de la cola B (y Mi gimnasio, la suplementación y las palancas), el doble.
    struct Entero: Transporte {
        let d: DobleColaB
        func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) {
            let ruta = p.url?.path ?? ""
            let f = ruta.components(separatedBy: "/").last ?? ""
            let suyas = ["mypump_gimnasio", "mypump_fin_plan", "mypump_compras", "mypump_casa"]
            if ruta.contains("/gimnasio/") || suyas.contains(where: f.hasPrefix) || f == "mypump_get_app_config" || f == "mypump_suplementacion" {
                return try await d.enviar(p)
            }
            let cuerpo = f == "mypump_get_cliente_info" ? #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"# : "[]"
            return (Data(cuerpo.utf8), HTTPURLResponse(url: p.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func app(_ d: DobleColaB) -> ModeloApp {
        ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: Entero(d: d), espera: 2), almacen: TokenEnMemoria(Self.token), raizDisco: raiz)
    }

    @Test func conLasPalancasApagadasNoSeLlamaANadaNuevo() async {
        let d = DobleColaB.escenario("apagado")
        let m = app(d)
        await m.cargar()
        try? await Task.sleep(for: .milliseconds(600))
        await m.alVolverAPrimerPlano()
        try? await Task.sleep(for: .milliseconds(600))
        #expect(d.llamadasNuevas.isEmpty, "\(d.llamadasNuevas)")
        #expect(m.recorrido?.estado == nil && m.compras?.hay == false && m.casa?.visible == false)
    }

    @Test func conLasPalancasPrendidasSeTraeTodo() async {
        let d = DobleColaB.escenario("todo")
        let m = app(d)
        await m.cargar()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(m.palanca.finPlan && m.palanca.comprasPais && m.palanca.casa)
        #expect(m.recorrido?.estado?.estado == .publicado)
        #expect(m.compras?.items.count == 2)
        #expect(m.casa?.visible == true)
        // La suplementación, una sola vez aunque la vuelta a primer plano caiga pegada a la carga.
        await m.alVolverAPrimerPlano()
        try? await Task.sleep(for: .milliseconds(600))
        #expect(d.cuantas("mypump_suplementacion") == 1, "\(d.cuantas("mypump_suplementacion"))")
    }

    @Test func sinSuplementacionNoSePreguntaDondeComprar() async {
        let d = DobleColaB.escenario("todo")
        d.suplementacion = nil
        let m = app(d)
        await m.cargar()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(d.cuantas("mypump_compras_get") == 0 && m.compras?.hay == false)
    }

    @Test func sinMiGimnasioParaLaCuentaNoSePreguntaPorCasa() async {
        let d = DobleColaB.escenario("todo")
        d.gimnasio.habilitado = false
        let m = app(d)
        await m.cargar()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(d.cuantas("mypump_casa_get") == 0 && m.casa?.visible == false)
    }
}

@Suite("Cola B: textos")
struct TextosColaBTests {
    @Test func ningunTextoUsaUnaPalabraVedada() {
        let vedadas = ["renov", "recompra", "venc", "vence", "coach", "entrenador", "pausa", "vacacion", "cuota", "precio", "descuento", "oferta", " rir ", "inteligencia", " ia ", " ia."]
        for t in TextosColaB.todos {
            let llano = " " + t.lowercased().folding(options: .diacriticInsensitive, locale: nil) + " "
            for v in vedadas { #expect(!llano.contains(v), "«\(t)» trae «\(v)»") }
            #expect(!t.isEmpty)
        }
    }
}
