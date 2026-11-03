import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
import MyPumpReloj
@testable import MyPumpDatos

// El Apple Watch del lado del iPhone (tanda 3): la rutina que se le manda al reloj sale del motor de Entreno, y los
// eventos del reloj entran a la cola de siempre por el mismo camino que un toque, sin duplicar con un reenvío y sin
// descartar nada en silencio (revisión del 3-nov).

let CUENTA = ModeloEntreno.hashCuenta("tok-prueba")
let MIN = 60_000.0

@Suite("Reloj: la rutina para el reloj y los eventos del reloj en el iPhone", .serialized)
@MainActor
struct RelojModeloTests {
    func ev(_ e: EventoReloj, _ t: Double = AHORA, cuenta: String? = CUENTA, rutina: String? = "rut-prueba") -> EventoEnCola {
        EventoEnCola(e, creado: t, cuenta: cuenta, rutinaId: rutina)
    }
    func serie(_ i: Int = 0, dia: String = "d1", semana: Int = 5, lugar: String = "jal-d1-0", reps: Int = 9, kg: Double? = 60,
               t: Double = AHORA, cuenta: String? = CUENTA, rutina: String? = "rut-prueba") -> EventoEnCola {
        ev(.serie(diaId: dia, semana: semana, lugar: lugar, indice: i, reps: reps, kg: kg), t, cuenta: cuenta, rutina: rutina)
    }

    @Test func laRutinaDelRelojEsLaDelDia() throws {
        let b = Banco()
        let m = b.modelo()
        let r = m.rutinaReloj()
        #expect(r.cuenta == CUENTA && r.cuenta.count == 16 && !r.cuenta.contains("tok"), "un hash, nunca el token")
        #expect(r.rutinaId == "rut-prueba")
        #expect(r.diaId == m.dia.dia.id)
        #expect(r.semana == 5)
        #expect(r.fecha == "2026-10-14")
        #expect(r.ejercicios.map(\.lugar) == m.dia.lista.map(\.id))
        let jalon = try #require(r.ejercicios.first)
        #expect(jalon.nombre == "Jalón al pecho")
        #expect(jalon.descansoSegundos == 150)
        #expect(jalon.series.count == 2)
        #expect(jalon.series.allSatisfy { !$0.confirmada })
        #expect(jalon.repsPlan == "10")
        #expect(jalon.series.first?.repsSugeridas == 10, "sin historial, lo del plan")
        #expect(jalon.musculo == "lats")
        // Viaja por el protocolo sin perder nada.
        let vuelta = try ProtocoloReloj.leer(ProtocoloReloj.diccionario(SobreReloj(.rutina(r), enviado: AHORA)))
        #expect(vuelta.mensaje == .rutina(r))
    }

    @Test func laPreparacionDelRelojEsLaMismaQueLaDelTelefono() throws {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "kg", valor: "60")
        var s = SesionReloj()
        s.recibir(m.rutinaReloj())
        // El teléfono con 60 kg escritos en la primera serie; el reloj con la corona en 60.
        s.girarKg(12) // 0 → 60 de 5 en 5 (polea: máquina)
        #expect(s.kg == 60)
        for l in m.dia.lista.map(\.id) {
            #expect(s.preparacion(l) == m.preparacion(l), "\(l)")
        }
    }

    @Test func unaSerieDelRelojEntraALaColaComoUnToque() async throws {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        let e = ev(.serie(diaId: "d1", semana: 5, lugar: "jal-d1-0", indice: 0, reps: 9, kg: 62.5))
        let acuses = await receptor.recibir([e], motor: m)
        #expect(acuses == [AcuseEvento(id: e.id, resultado: .aplicado)])
        let serie = try #require(m.dia.ejercicios["jal-d1-0"]?.series[0])
        #expect(serie.confirmada && serie.reps == "9" && serie.kg == "62.5")
        let ops = await b.cola.operaciones.filter { $0.kind == "carga" }
        #expect(ops.count == 1)
        #expect(m.descanso.descanso != nil, "arranca el descanso también en el teléfono")
        // El mismo evento otra vez (el reloj no recibió el acuse): no se duplica, ni después de reabrir.
        let otra = ReceptorReloj(disco: b.disco)
        #expect(await otra.recibir([e], motor: m) == [AcuseEvento(id: e.id, resultado: .repetido)])
        #expect(await b.cola.operaciones.filter { $0.kind == "carga" }.count == 1)
    }

    @Test func unaSerieCorregidaEnElRelojSeCorrigeEnElTelefono() async throws {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        _ = await receptor.recibir([ev(.serie(diaId: "d1", semana: 5, lugar: "jal-d1-0", indice: 0, reps: 9, kg: 60))], motor: m)
        let corregida = ev(.serie(diaId: "d1", semana: 5, lugar: "jal-d1-0", indice: 0, reps: 10, kg: 60), AHORA + 1)
        #expect(await receptor.recibir([corregida], motor: m).first?.resultado == .aplicado)
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].reps == "10")
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].confirmada == true)
        let ops = await b.cola.operaciones.filter { $0.kind == "carga" }
        #expect(ops.count == 1, "la cola deja la última por clave")
        #expect(ops.first?.payload["datos"]?["reps"]?.comoNumero == 10)
    }

    // MARK: - 1. Nada se descarta en silencio

    @Test func loQueNoSePuedeAplicarNuncaSeRechazaConMotivo() async throws {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        let a = await receptor.recibir([serie(semana: 4, t: AHORA - 4), serie(t: AHORA - 3, rutina: "rut-vieja"),
                                        serie(7, t: AHORA - 2), serie(dia: "d9", lugar: "x", t: AHORA - 1)], motor: m)
        #expect(a.map(\.resultado) == [.rechazado, .rechazado, .rechazado, .rechazado])
        #expect(a[0].motivo == "el iPhone ya pasó a la semana 5.")
        #expect(a[1].motivo == "tu rutina cambió desde que la hiciste.")
        #expect(a.allSatisfy { !($0.motivo ?? "").isEmpty })
        #expect(await b.cola.operaciones.isEmpty)
        #expect(m.dia.dia.id == "d1")
        // Y el reloj se lo muestra al alumno.
        var s = SesionReloj()
        s.recibir(m.rutinaReloj())
        s.confirmar(ahora: AHORA)
        let e = try #require(s.cola.pendientes.last)
        #expect(e.cuenta == CUENTA && e.rutinaId == "rut-prueba", "los eventos llevan la cuenta y la rutina")
        s.acusar([AcuseEvento(id: e.id, resultado: .rechazado, motivo: "tu rutina cambió desde que la hiciste.")])
        #expect(s.rechazos == ["Esta serie no se pudo guardar: tu rutina cambió desde que la hiciste."])
    }

    @Test func loQueNoSePuedeAplicarAhoraQuedaPendiente() async {
        let b = Banco()
        let receptor = ReceptorReloj(disco: b.disco)
        let e = serie()
        #expect(await receptor.recibir([e], motor: nil).first?.resultado == .pendiente, "sin cuenta en el iPhone")
        let m = b.modelo()
        #expect(await receptor.recibir([serie(cuenta: "otra")], motor: m).first?.motivo == "El iPhone tiene otra cuenta abierta.")
        let demo = b.modelo(token: nil)
        #expect(await ReceptorReloj(disco: nil).recibir([e], motor: demo).first?.resultado == .pendiente, "el iPhone en la demo")
        #expect(await receptor.recibir([serie(semana: 6)], motor: m).first?.resultado == .pendiente, "una semana a la que no llegó")
        #expect(await b.cola.operaciones.isEmpty)
        // Pendiente no queda anotado: cuando se puede, se aplica.
        #expect(await receptor.recibir([e], motor: m).first?.resultado == .aplicado)
    }

    @Test func laColaDelRelojGuardaLosPendientesYLosReintenta() {
        var c = ColaReloj()
        let e = serie()
        c.encolar(e)
        _ = c.paraEnviar(ahora: AHORA)
        let salen = c.acusar([AcuseEvento(id: e.id, resultado: .pendiente, motivo: "x")], ahora: AHORA + 1_000)
        #expect(salen.isEmpty && c.pendientes.map(\.id) == [e.id])
        #expect(c.paraEnviar(ahora: AHORA + 2_000).isEmpty)
        #expect(c.paraEnviar(ahora: AHORA + 1_000 + ColaReloj.reintento).count == 1)
    }

    // MARK: - 2. La hora del reloj

    @Test func elCronometroYElDescansoSalenDeCuandoPasoEnElReloj() async throws {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        let inicio = AHORA - 40 * MIN
        _ = await receptor.recibir([ev(.iniciar(diaId: "d1", semana: 5), inicio)], motor: m)
        #expect(m.inicioSesion == inicio)
        // Una serie de hace 10 min: su descanso de 150 s ya terminó, no arranca uno nuevo.
        _ = await receptor.recibir([serie(t: AHORA - 10 * MIN)], motor: m)
        #expect(m.descanso.guardado == nil)
        // Una de hace 30 s: el descanso va anclado a cuando se hizo.
        _ = await receptor.recibir([serie(1, t: AHORA - 30_000)], motor: m)
        let d = try #require(m.descanso.guardado)
        #expect(d.endsAt == AHORA - 30_000 + 150_000)
    }

    @Test func unaSerieDeAyerSeFechaAyerYArrancaElCronometro() async {
        let b = Banco()
        let m = b.modelo()
        let ayer = AHORA - 24 * 60 * MIN
        _ = await ReceptorReloj(disco: b.disco).recibir([serie(t: ayer)], motor: m)
        #expect(m.fechasSeries[m.claveFecha("jal-d1-0", 1)] == "2026-10-13")
        #expect(m.inicioSesion == ayer)
    }

    @Test func laDuracionDelCierreTerminaCuandoSeTerminoEnElReloj() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T17:00:00Z"))
        b.servidor.cuando("registrar_carga", #""fila-1""#)
        b.servidor.cuando("finalizar_sesion", "true")
        let m = b.modelo()
        await m.restaurarSesion()
        let a = await ReceptorReloj(disco: b.disco).recibir([serie(t: AHORA - 50 * MIN), ev(.terminar(diaId: "d1", semana: 5), AHORA - 20 * MIN)], motor: m)
        #expect(a.map(\.resultado) == [.aplicado, .aplicado])
        let fin = try #require(b.servidor.llamadas("finalizar_sesion").first)
        #expect(fin["p_duracion_segundos"] == .numero(40 * 60), "de las 14:00 a las 14:40, no hasta que llegó")
        #expect(m.dia.diaFinalizado)
    }

    // MARK: - 3. Otro día abierto

    @Test func otroDiaConAlgoEnCursoNoCambiaLaPantallaYQuedaPendiente() async {
        let b = Banco()
        let m = b.modelo()
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "12")
        let receptor = ReceptorReloj(disco: b.disco)
        let e = serie(dia: "d2", lugar: "pre-d2-0", reps: 8, kg: 80)
        #expect(await receptor.recibir([e], motor: m).first?.resultado == .pendiente)
        #expect(m.dia.dia.id == "d1", "no se cambió de día")
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[0].reps == "12", "lo tipeado sigue ahí")
        // Sin nada en curso, se abre el día del reloj y se aplica.
        m.escribir("jal-d1-0", 0, campo: "reps", valor: "")
        #expect(await receptor.recibir([e], motor: m).first?.resultado == .aplicado)
        #expect(m.dia.dia.id == "d2")
        #expect(m.dia.ejercicios["pre-d2-0"]?.series[0].confirmada == true)
    }

    // MARK: - 5. Un «terminar» que no sale no traba la cola

    @Test func unTerminarSinRedNoTrabaLosDeAtras() async {
        let b = Banco()
        let m = b.modelo()
        b.servidor.sinRed("iniciar_sesion")
        let receptor = ReceptorReloj(disco: b.disco)
        _ = await receptor.recibir([serie(t: AHORA - 2)], motor: m)
        let a = await receptor.recibir([ev(.terminar(diaId: "d1", semana: 5), AHORA - 1), serie(1, t: AHORA)], motor: m)
        #expect(a.map(\.resultado) == [.pendiente, .aplicado])
        #expect(m.dia.ejercicios["jal-d1-0"]?.series[1].confirmada == true)
    }

    @Test func iniciarArrancaLaSesion() async {
        let b = Banco()
        let m = b.modelo()
        let e = ev(.iniciar(diaId: "d1", semana: 5))
        #expect(await ReceptorReloj(disco: b.disco).recibir([e], motor: m) == [AcuseEvento(id: e.id, resultado: .aplicado)])
        #expect(m.inicioSesion == AHORA)
        #expect(m.iniciadaConBoton)
    }

    // MARK: - Reentrada

    @Test func unLoteDuplicadoEnElMedioNoAplicaDosVeces() async {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-1", iniciada: "2026-10-14T17:00:00Z"))
        b.servidor.cuando("registrar_carga", #""fila-1""#)
        b.servidor.regla("finalizar_sesion") { _ in await demora(200); return (200, "true") }
        let m = b.modelo()
        await m.restaurarSesion()
        let receptor = ReceptorReloj(disco: b.disco)
        _ = await receptor.recibir([serie(t: AHORA - 1)], motor: m)
        let fin = ev(.terminar(diaId: "d1", semana: 5))
        async let uno = receptor.recibir([fin], motor: m)
        async let dos = receptor.recibir([fin], motor: m)
        let (a, c) = await (uno, dos)
        #expect(Set((a + c).map(\.resultado)) == [.aplicado, .pendiente])
        #expect(b.servidor.llamadas("finalizar_sesion").count == 1)
        #expect(await receptor.recibir([fin], motor: m).first?.resultado == .repetido)
    }

    // MARK: - Versión

    @Test func unRelojMasNuevoRecibeLaVersionDelIPhoneYDejaDeReenviar() throws {
        let nuevo: [String: Any] = [ProtocoloReloj.claveVersion: ProtocoloReloj.version + 1,
                                    ProtocoloReloj.claveMensaje: Data(#"{"v":\#(ProtocoloReloj.version + 1),"id":"x"}"#.utf8)]
        let resp = try #require(ProtocoloReloj.respuestaIncompatible(nuevo, ahora: AHORA))
        let sobre = try ProtocoloReloj.leer(resp)
        #expect(sobre.mensaje == .incompatible(version: ProtocoloReloj.version))
        #expect(try ProtocoloReloj.respuestaIncompatible(ProtocoloReloj.diccionario(SobreReloj(.pedirRutina, enviado: AHORA)), ahora: AHORA) == nil)
        let b = Banco()
        var s = SesionReloj()
        s.recibir(b.modelo().rutinaReloj())
        s.confirmar(ahora: AHORA)
        s.marcarIncompatible(version: ProtocoloReloj.version - 1)
        #expect(s.incompatible == "Actualizá Pump Team en el iPhone para usar el reloj.")
        #expect(s.paraEnviar(ahora: AHORA, forzar: true).isEmpty && s.cola.pendientes.count == 2, "guardado, sin reenviar")
        s.recibir(b.modelo().rutinaReloj())
        #expect(s.incompatible == nil)
    }
}
