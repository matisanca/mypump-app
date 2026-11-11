import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// La cola y el recorrido de «Presión arterial» contra el doble que sigue el contrato (`presion/CONTRATO_APP.md`).
@MainActor
struct PresionModeloTests {
    private let token = "tk-prueba-presion"

    private func armar(_ d: DoblePresion, raiz: URL? = nil) -> (ModeloPresion, URL) {
        let r = raiz ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token)), r)
    }
    private func json(_ s: String) -> JSONValue { (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null }
    /// Deja pasar lo que quedó drenando en segundo plano.
    private func asentar(_ m: ModeloPresion) async {
        for _ in 0..<20 { await Task.yield() }
        await m.drenar()
    }

    // MARK: Palanca

    @Test func palancaDeFabricaApagadaYSeRecuerda() {
        #expect(!PalancaRemota.deFabrica.presionApp)
        #expect(!PalancaRemota(.objeto([:])).presionApp)
        #expect(!PalancaRemota(.objeto(["presion_app": .texto("true")])).presionApp)
        #expect(PalancaRemota(.objeto(["presion_app": .bool(true)])).presionApp)
        let d = UserDefaults(suiteName: "presion-\(UUID().uuidString)")!
        #expect(!PalancaRemota.arranque(defaults: d).presionApp)
        PalancaRemota(.objeto(["presion_app": .bool(true)])).recordar(defaults: d)
        #expect(PalancaRemota.arranque(defaults: d).presionApp)
        PalancaRemota(.objeto(["presion_app": .bool(false)])).recordar(defaults: d)
        #expect(!PalancaRemota.arranque(defaults: d).presionApp)
    }

    @Test func palancaApagadaNoLlamaANada() async {
        let d = DoblePresion.escenario("apagado")
        let leida = await PalancaRemota.leer(ClienteRPC(transporte: d))
        #expect(leida?.presionApp == false)
        let (m, _) = armar(d)
        // Lo que hace `ModeloApp.sincronizarPresion` con la palanca apagada.
        m.apagar()
        #expect(!m.habilitado)
        #expect(await m.guardarMedida(35) == .error)
        #expect(await m.guardarAparato(Presion.Aparato(tipo: "brazo")) == .error)
        m.marcarSintoma(codigos: ["palpitaciones"], nota: nil)
        await asentar(m)
        #expect(d.llamadasPresion.isEmpty)
    }

    @Test func sinElServidorNuevoONoHabilitadoNoSeVeNada() async {
        let d = DoblePresion.escenario("sinServidor")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(!m.habilitado)
        let h = DoblePresion.escenario("serie0"); h.habilitado = false
        let (m2, _) = armar(h)
        await m2.refrescar()
        #expect(!m2.habilitado)
        let c = DoblePresion.escenario("serie0"); c.tokenCaido = true
        let (m3, _) = armar(c)
        await m3.refrescar()
        #expect(!m3.habilitado)
    }

    // MARK: Aparato y medida

    @Test func aparatoYMedida() async {
        let d = DoblePresion.escenario("vacio")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.habilitado)
        #expect(m.estado?.aparato == nil)
        #expect(await m.guardarMedida(19.9) == .error)
        #expect(d.cuantas("mypump_presion_medida") == 0)
        #expect(await m.guardarMedida(35.44) == .ok)
        #expect(m.estado?.circunferenciaBrazoCm == 35.4)
        #expect(await m.guardarAparato(Presion.Aparato(tipo: "brazo", marca: " Marca ", modelo: "", manguitoMinCm: 22, manguitoMaxCm: 42)) == .ok)
        #expect(m.estado?.aparato?.tipo == "brazo")
        #expect(m.estado?.aparato?.marca == "Marca")
        #expect(m.estado?.aparato?.modelo == nil)
        #expect(Presion.manguitoCalza(m.estado?.circunferenciaBrazoCm, m.estado?.aparato) == true)
        d.sinRed = true
        #expect(await m.guardarMedida(36) == .sinSenal)
    }

    // MARK: Sesión

    @Test func tomaComunCompletaLaSerieDeADia() async {
        let d = DoblePresion.escenario("serie2")
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.estado?.serie?.faltan == 1)
        #expect(m.estado?.serie?.dias.count == 2)
        m.empezar(tipo: "estandar", serieId: m.estado?.serie?.id, brazo: "izq", etapa: "anotar")
        m.cambiar { $0.sesion.reposoCumplido = true; $0.sesion.temporizadorSalteado = false }
        let ev = m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)
        #expect(ev?.paso == .listo)
        #expect(ev?.cuenta == true)
        await asentar(m)
        #expect(m.enCola == 0)
        #expect(m.estado?.serie?.faltan == 0)
        #expect(m.estado?.sesiones.first?.tomas.first?.sis == 124)
        let p = d.recibidas.last
        #expect(p?["plataforma"]?.comoTexto == "ios")
        #expect(p?["texto_alumno"]?.comoTexto == "ninguno")
        #expect(p?["serie_id"]?.comoTexto == DoblePresion.idSerie)
        #expect(p?["reposo_cumplido"] == .bool(true))
        #expect(p?["tomas"] != nil)
        #expect(p?["zona_horaria"]?.comoTexto?.isEmpty == false)
        m.terminar()
        #expect(m.enCurso == nil)
    }

    @Test func valorImposibleNoSeAnota() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        #expect(m.anotarToma(sis: 300, dia: 80, pulso: 60, latidoIrregular: false) == nil)
        #expect(m.anotarToma(sis: 100, dia: 95, pulso: 60, latidoIrregular: false) == nil)
        #expect(m.enCurso?.sesion.tomas.isEmpty == true)
        await asentar(m)
        #expect(d.cuantas("mypump_presion_sesion") == 0)
    }

    @Test func tomaAltaPideRepetirYConfirmada() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.cambiar { $0.sesion.reposoCumplido = true }
        #expect(m.anotarToma(sis: 160, dia: 100, pulso: 70, latidoIrregular: false, confirmada: true)?.paso == .repetir)
        await asentar(m)
        #expect(m.estado?.pendiente?.nivel == "alta")
        let ev = m.anotarToma(sis: 164, dia: 101, pulso: 72, latidoIrregular: false, confirmada: true)
        #expect(ev?.paso == .listo)
        #expect(ev?.reglas == ["alta_toma_160_100"])
        await asentar(m)
        #expect(m.estado?.pendiente == nil)
        #expect(d.sesiones.count == 1)
        #expect(m.estado?.sesiones.first?.tomas.count == 2)
    }

    @Test func urgenciaListaYGuardia() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        #expect(m.anotarToma(sis: 182, dia: 120, pulso: 80, latidoIrregular: false, confirmada: true)?.paso == .repetirConLista)
        // Sin contestar no es «no».
        #expect(m.enCurso?.sesion.listaEspera == nil)
        for c in Presion.alarma.dropLast() { #expect(m.responderLista(c, false)?.paso == .repetirConLista) }
        #expect(m.enCurso?.sesion.listaEspera == nil)
        #expect(m.responderLista(Presion.alarma.last!, false)?.paso == .repetirConLista)
        #expect(m.enCurso?.sesion.listaEspera == "no")
        // Todos en No y la repetición sigue alta: guardia por presión.
        let ev = m.anotarToma(sis: 181, dia: 110, pulso: 82, latidoIrregular: false, confirmada: true)
        #expect(ev?.paso == .guardiaPresion)
        #expect(ev?.texto == "guardia_presion")
        await asentar(m)
        #expect(d.recibidas.last?["texto_alumno"]?.comoTexto == "guardia_presion")
        #expect(d.sesiones.count == 1)

        // Un Sí en la espera: guardia por síntomas en el acto, y aunque no haya red.
        let d2 = DoblePresion.escenario("serie0")
        let (m2, _) = armar(d2)
        await m2.refrescar()
        d2.sinRed = true
        m2.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        #expect(m2.anotarToma(sis: 182, dia: 120, pulso: 80, latidoIrregular: false, confirmada: true)?.paso == .repetirConLista)
        let ev2 = m2.responderLista("dolor_pecho", true)
        #expect(ev2?.paso == .guardiaSintomas)
        #expect(ev2?.reglas.contains("sintoma_alarma_en_espera") == true)
        #expect(m2.enCurso?.sesion.listaEspera == "si")
        #expect(m2.enCola == 1)
    }

    // MARK: Cola

    @Test func sinRedQuedaEnColaYSaleAlReintentar() async {
        let d = DoblePresion.escenario("serie0")
        let (m, r) = armar(d)
        await m.refrescar()
        d.sinRed = true
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.cambiar { $0.sesion.reposoCumplido = true }
        #expect(m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)?.paso == .listo)
        #expect(m.marcarSintoma(codigos: ["palpitaciones"], nota: " hoy ") == false)
        await asentar(m)
        #expect(m.enCola == 2)
        #expect(d.sesiones.isEmpty)
        // Se cerró la app: otro modelo, la misma carpeta, todavía sin red. Arranca de lo guardado.
        let (m2, _) = armar(d, raiz: r)
        await m2.refrescar()
        #expect(m2.habilitado)
        #expect(m2.enCola == 2)
        #expect(m2.enCurso?.sesion.tomas.count == 1)
        await m2.drenar()
        #expect(m2.enCola == 2)
        d.sinRed = false
        await m2.drenar()
        #expect(m2.enCola == 0)
        #expect(d.sesiones.count == 1)
        #expect(d.sintomas.count == 1)
        #expect(d.sintomas.first?["nota"]?.comoTexto == "hoy")
        #expect(d.sintomas.first?["contexto"]?.comoTexto == "boton")
        // En orden: primero la sesión, después el síntoma.
        let escrituras = d.llamadasPresion.filter { $0 == "mypump_presion_sesion" || $0 == "mypump_presion_sintoma" }
        #expect(escrituras.suffix(2) == ["mypump_presion_sesion", "mypump_presion_sintoma"])
        #expect(m2.estado?.serie?.faltan == 2)
    }

    @Test func cincoXXY429NoGastanElEnvio() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        d.proximas = [503, 429, 0]
        m.marcarSintoma(codigos: ["mareo_al_pararse"], nota: nil)
        await asentar(m)
        #expect(m.enCola == 1)
        // `asentar` ya gastó el 503 y el 429; queda el corte de red.
        await m.drenar()
        #expect(m.enCola == 1)
        #expect(d.sintomas.isEmpty)
        await m.drenar()
        #expect(m.enCola == 0)
        #expect(d.sintomas.count == 1)
        #expect(d.cuantas("mypump_presion_sintoma") == 4)
    }

    @Test func cuatroXXYOkFalseSeDescartanYRefrescan() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        d.proximas = [400]
        let antes = d.cuantas("mypump_presion_get")
        m.marcarSintoma(codigos: ["palpitaciones"], nota: nil)
        await asentar(m)
        #expect(m.enCola == 0)
        #expect(d.sintomas.isEmpty)
        #expect(d.cuantas("mypump_presion_get") == antes + 1)
        #expect(m.habilitado)

        d.proximoError = "serie"
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)
        m.marcarSintoma(codigos: ["vomitos_diarrea"], nota: nil)
        await asentar(m)
        // La sesión rechazada se descarta y lo que sigue en la cola sale igual.
        #expect(m.enCola == 0)
        #expect(d.sesiones.isEmpty)
        #expect(d.sintomas.count == 1)
        #expect(d.cuantas("mypump_presion_get") == antes + 2)
    }

    @Test func idempotenteAunqueSeCorteDespuesDeGuardar() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.cambiar { $0.sesion.reposoCumplido = true }
        m.anotarToma(sis: 162, dia: 96, pulso: 70, latidoIrregular: false, confirmada: true)
        await asentar(m)
        #expect(d.sesiones.count == 1)
        // La segunda toma viaja con la sesión entera: el servidor no duplica la sesión ni pisa la primera toma.
        m.anotarToma(sis: 150, dia: 92, pulso: 68, latidoIrregular: true, confirmada: false)
        await asentar(m)
        #expect(d.sesiones.count == 1)
        #expect(d.cuantas("mypump_presion_sesion") == 2)
        guard case .lista(let tomas)? = d.sesiones.first?["tomas"] else { Issue.record("sin tomas"); return }
        #expect(tomas.count == 2)
        #expect(tomas.first?["sis"]?.comoNumero == 162)
        #expect(d.recibidas.last?["id"] == d.recibidas.first?["id"])
        // El mismo síntoma mandado dos veces queda una sola vez.
        let s = SintomaPresion(id: "55555555-5555-4555-8555-555555555555", marcadoEn: "2026-11-10T10:00:00Z", zonaHoraria: "UTC", contexto: "boton", sesionId: nil, codigos: ["palpitaciones"], sinSintomasEnLista: nil, nota: nil)
        let c = ClienteRPC(transporte: d)
        _ = await c.llamar("mypump_presion_sintoma", ["p_token": .texto(token), "p_sintoma": ModeloPresion.json(s)])
        _ = await c.llamar("mypump_presion_sintoma", ["p_token": .texto(token), "p_sintoma": ModeloPresion.json(s)])
        #expect(d.sintomas.count == 1)
    }

    @Test func unaVersionMasNuevaDeLaSesionReemplazaALaQueEspera() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        d.sinRed = true
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.anotarToma(sis: 165, dia: 96, pulso: 70, latidoIrregular: false, confirmada: true)
        m.anotarToma(sis: 150, dia: 92, pulso: 68, latidoIrregular: false)
        await asentar(m)
        #expect(m.enCola == 1)
        d.sinRed = false
        await m.drenar()
        #expect(d.sesiones.count == 1)
        guard case .lista(let tomas)? = d.sesiones.first?["tomas"] else { Issue.record("sin tomas"); return }
        #expect(tomas.count == 2)
    }

    @Test func laSesionEnCursoSeRetomaElMismoDiaYNoAlOtro() async {
        let d = DoblePresion.escenario("serie0")
        let (m, r) = armar(d)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: "der", etapa: "reposo")
        let fin = Date().addingTimeInterval(300)
        m.cambiar { $0.etapa = "espera"; $0.finTemporizador = fin }
        let (m2, _) = armar(d, raiz: r)
        #expect(m2.enCurso?.etapa == "espera")
        #expect(m2.enCurso?.sesion.brazo == "der")
        #expect(abs((m2.enCurso?.finTemporizador ?? .distantPast).timeIntervalSince(fin)) < 1)
        let manana = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token), ahora: { Date().addingTimeInterval(36 * 3600) })
        #expect(manana.enCurso == nil)
    }

    @Test func retomarLaRepeticionQuePideElServidor() async {
        let d = DoblePresion.escenario("pendienteUrgencia")
        let (m, _) = armar(d)
        await m.refrescar()
        let p = m.estado?.pendiente
        #expect(p?.nivel == "urgencia")
        guard let p else { return }
        m.retomar(p, etapa: "anotar")
        #expect(m.enCurso?.sesion.tomas.count == 1)
        #expect(m.enCurso?.sesion.id == p.sesionId)
        #expect(m.anotarToma(sis: 150, dia: 90, pulso: 70, latidoIrregular: false)?.paso == .listo)
        await asentar(m)
        #expect(m.estado?.pendiente == nil)
        // La lista del recordatorio viaja como síntoma.
        #expect(m.marcarSintoma(codigos: [], nota: nil, contexto: "recordatorio_180_120", sesionId: p.sesionId, sinSintomasEnLista: true) == false)
        #expect(m.marcarSintoma(codigos: ["confusion"], nota: nil, contexto: "recordatorio_180_120", sesionId: p.sesionId, sinSintomasEnLista: false) == true)
        await asentar(m)
        #expect(d.sintomas.count == 2)
        #expect(d.sintomas.first?["sin_sintomas_en_lista"] == .bool(true))
    }

    // MARK: Tarjeta de arriba, cola sin servidor y vencimiento

    @Test func tarjetaLosEstadosEnElOrdenDelContrato() async {
        func tarjeta(_ escenario: String) async -> ModeloPresion.Tarjeta? {
            let (m, _) = armar(DoblePresion.escenario(escenario))
            await m.refrescar()
            return m.tarjeta
        }
        #expect(await tarjeta("sinServidor") == nil)
        #expect(await tarjeta("sinSerie") == nil)
        #expect(await tarjeta("vacio") == nil, "sin serie abierta no hay tarjeta aunque falte el aparato")
        #expect(await tarjeta("serie0") == .toma(hechas: 0, total: 3, faltan: 3))
        #expect(await tarjeta("serie2") == .toma(hechas: 2, total: 3, faltan: 1))
        #expect(await tarjeta("medirDeNuevo") == .preparar)
        #expect(await tarjeta("hoyListo") == .hoyListo(hechas: 2, total: 3))
        #expect(await tarjeta("pendienteUrgencia") == .repetir)
        #expect(await tarjeta("pendienteAlta") == .repetir)
        // Serie abierta sin aparato, o con reloj: primero preparar.
        let d = DoblePresion.escenario("serie0")
        d.aparato = nil
        let (m, _) = armar(d)
        await m.refrescar()
        #expect(m.tarjeta == .preparar)
        d.aparato = ["id": .texto("a"), "tipo": .texto("reloj_anillo_otro")]
        await m.refrescar()
        #expect(m.tarjeta == .preparar)
    }

    @Test func tarjetaSigueALoAnotadoSinSenal() async {
        let d = DoblePresion.escenario("serie0")
        let (m, _) = armar(d)
        await m.refrescar()
        d.sinRed = true
        m.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m.cambiar { $0.sesion.reposoCumplido = true }
        #expect(m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)?.paso == .listo)
        await asentar(m)
        #expect(m.estado?.serie?.faltan == 3, "el servidor todavía no se enteró")
        #expect(m.hoyListo)
        #expect(m.tarjeta == .hoyListo(hechas: 1, total: 3))
        m.terminar()
        #expect(m.tarjeta == .hoyListo(hechas: 1, total: 3))
        // Una toma que pide repetición: la tarjeta lleva a repetir, con la sesión todavía en el teléfono.
        let (m2, _) = armar(DoblePresion.escenario("serie0"))
        await m2.refrescar()
        m2.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        #expect(m2.anotarToma(sis: 164, dia: 98, pulso: 70, latidoIrregular: false, confirmada: true)?.paso == .repetir)
        #expect(m2.tarjeta == .repetir)
        #expect(m2.pendiente?.nivel == "alta")
    }

    @Test func un404NoBorraLaColaYSaleCuandoVuelveElServidor() async {
        for sinFuncion in [true, false] {
            let d = DoblePresion.escenario("serie0")
            let (m, r) = armar(d)
            await m.refrescar()
            if sinFuncion { d.sinFuncion = true } else { d.proximas = [404] }
            m.marcarSintoma(codigos: ["palpitaciones"], nota: nil)
            await asentar(m)
            #expect(!m.habilitado, "sin el servidor nuevo se apaga")
            #expect(m.enCola == 1, "y lo anotado queda guardado")
            #expect(m.tarjeta == nil)
            // Otro arranque, el servidor volvió: la cola sale.
            d.sinFuncion = false
            d.proximas = []
            let (m2, _) = armar(d, raiz: r)
            #expect(m2.enCola == 1)
            await m2.refrescar()
            await m2.drenar()
            #expect(m2.enCola == 0)
            #expect(d.sintomas.count == 1)
        }
    }

    @Test func laColaVenceALos30Dias() async {
        let d = DoblePresion.escenario("serie0")
        let r = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let hace31 = Date().addingTimeInterval(-31 * 86_400)
        let viejo = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token), ahora: { hace31 })
        await viejo.refrescar()
        d.sinRed = true
        viejo.marcarSintoma(codigos: ["palpitaciones"], nota: nil)
        await asentar(viejo)
        #expect(viejo.enCola == 1)
        // A los 29 días sigue; a los 31, ya no.
        let hace2 = Date().addingTimeInterval(-2 * 86_400)
        let casi = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token), ahora: { hace2 })
        #expect(casi.enCola == 1)
        let (hoy, _) = armar(d, raiz: r)
        #expect(hoy.enCola == 0)
    }

    @Test func laRepeticionRetomadaViajaConElMismoIdYSinInventarLasPrevias() async {
        let d = DoblePresion.escenario("pendienteAlta")
        let (m, _) = armar(d)
        await m.refrescar()
        guard let p = m.pendiente else { Issue.record("sin pendiente"); return }
        m.retomar(p, etapa: "anotar")
        #expect(m.anotarToma(sis: 150, dia: 90, pulso: 70, latidoIrregular: false)?.paso == .listo)
        await asentar(m)
        guard let enviada = d.recibidas.last else { Issue.record("no viajó"); return }
        #expect(enviada["id"]?.comoTexto == p.sesionId)
        #expect(enviada["previo"] == .null)
        #expect(enviada["reposo_cumplido"] == .null)
        if case .lista(let tomas)? = enviada["tomas"] { #expect(tomas.count == 2) } else { Issue.record("sin tomas") }
        #expect(m.estado?.pendiente == nil)
        // Una sesión común sí manda sus previas.
        let d2 = DoblePresion.escenario("serie0")
        let (m2, _) = armar(d2)
        await m2.refrescar()
        m2.empezar(tipo: "estandar", serieId: DoblePresion.idSerie, brazo: nil, etapa: "anotar")
        m2.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)
        await asentar(m2)
        #expect(d2.recibidas.last?["previo"]?["cafeina"] == .bool(false))
    }

    // MARK: Decodificación

    @Test func decodificacionTolerante() {
        #expect(EstadoPresion(json(#"{"habilitado":false}"#)) == nil)
        #expect(EstadoPresion(json(#"{"habilitado":"si"}"#)) == nil)
        #expect(EstadoPresion(json("[]")) == nil)
        let minimo = EstadoPresion(json(#"{"habilitado":true}"#))
        #expect(minimo != nil)
        #expect(minimo?.aparato == nil && minimo?.serie == nil && minimo?.sesiones.isEmpty == true && minimo?.pendiente == nil && minimo?.tensiometros == nil && minimo?.fotos == false)
        // Tipos cambiados, campos de más y filas rotas: lo que no se entiende se descarta, lo demás queda.
        let raro = EstadoPresion(json(#"""
        {"habilitado":true,"fotos":"si","hoy":20261110,"algo_nuevo":{"x":1},
         "aparato":{"tipo":"brazo","validado":7,"manguito_min_cm":"22","manguito_max_cm":42,"otro":true},
         "circunferencia_brazo_cm":"35",
         "serie":{"id":"s1","tipo":"rara","tomas_objetivo":"tres","dias":["2026-11-08",9,null],"ortostatica":"de_cabeza","comparar_brazos":"si","medida_pedida":true},
         "sesiones":[{"id":"a","fecha":"2026-11-08","tipo":"estandar","cuenta":true,"tomas":[{"orden":2,"sis":130,"dia":82,"pulso":60},{"orden":1,"sis":"x","dia":80,"pulso":60},{"sis":128,"dia":80,"pulso":61,"latido_irregular":true}]},
                     {"fecha":"2026-11-07"},7,{"id":"b","tomas":"ninguna"}],
         "pendiente":{"nivel":"urgencia"},
         "tensiometros":{"version":3,"tramos":{"estandar":[{"nombre":"Uno","codigo":"A-1"},{"codigo":"sin nombre"}],"grande":"no"}}}
        """#))
        #expect(raro != nil)
        #expect(raro?.fotos == false)
        #expect(raro?.hoy == nil)
        #expect(raro?.aparato?.tipo == "brazo")
        #expect(raro?.aparato?.validado == nil)
        #expect(raro?.aparato?.manguitoMinCm == nil)
        #expect(raro?.aparato?.manguitoMaxCm == 42)
        #expect(raro?.circunferenciaBrazoCm == nil)
        #expect(raro?.serie?.tipo == "estandar")
        #expect(raro?.serie?.tomasObjetivo == 3)
        #expect(raro?.serie?.dias == ["2026-11-08"])
        #expect(raro?.serie?.faltan == 2)
        #expect(raro?.serie?.ortostatica == nil)
        #expect(raro?.serie?.compararBrazos == false)
        #expect(raro?.serie?.medidaPedida == true)
        #expect(raro?.sesiones.map(\.id) == ["a", "b"])
        #expect(raro?.sesiones.first?.tomas.map(\.sis) == [128, 130])
        #expect(raro?.sesiones.first?.tomas.first?.latidoIrregular == true)
        #expect(raro?.sesiones.last?.tomas.isEmpty == true)
        #expect(raro?.pendiente == nil)
        #expect(raro?.tensiometros?.version == "3")
        #expect(raro?.tensiometros?.tramos["estandar"]?.map(\.nombre) == ["Uno"])
        #expect(raro?.tensiometros?.tramos["grande"]?.isEmpty == true)
    }

    @Test func losEscenariosDelDobleArrancan() async {
        for (nombre, conAparato, conSerie) in [("vacio", false, false), ("sinSerie", true, false), ("serie0", true, true), ("serie2", true, true), ("pendienteUrgencia", true, true),
                                               ("completa", true, true), ("muneca", true, true), ("bajoEfecto", true, true), ("ortostatica", true, true)] {
            let (m, _) = armar(DoblePresion.escenario(nombre))
            await m.refrescar()
            #expect(m.habilitado, "\(nombre)")
            #expect((m.estado?.aparato != nil) == conAparato, "\(nombre)")
            #expect((m.estado?.serie != nil) == conSerie, "\(nombre)")
        }
        let (c, _) = armar(DoblePresion.escenario("completa"))
        await c.refrescar()
        #expect(c.estado?.serie?.faltan == 0)
        #expect(c.estado?.sesiones.count == 3)
        let (u, _) = armar(DoblePresion.escenario("muneca"))
        await u.refrescar()
        #expect(Presion.metodo(u.estado?.circunferenciaBrazoCm, u.estado?.aparato).metodo == "muneca_provisoria")
        let (o, _) = armar(DoblePresion.escenario("ortostatica"))
        await o.refrescar()
        #expect(o.estado?.serie?.ortostatica == "acostado_parado")
        let (b, _) = armar(DoblePresion.escenario("bajoEfecto"))
        await b.refrescar()
        #expect(b.estado?.serie?.tipo == "bajo_efecto")
    }
}
