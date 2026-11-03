import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
import MyPumpReloj
@testable import MyPumpDatos

// El Apple Watch del lado del iPhone (tanda 3): la rutina que se le manda al reloj sale del motor de Entreno, y los
// eventos del reloj entran a la cola de siempre por el mismo camino que un toque, sin duplicar con un reenvío.

@Suite("Reloj: la rutina para el reloj y los eventos del reloj en el iPhone", .serialized)
@MainActor
struct RelojModeloTests {
    func ev(_ e: EventoReloj, _ t: Double = AHORA) -> EventoEnCola { EventoEnCola(e, creado: t) }

    @Test func laRutinaDelRelojEsLaDelDia() throws {
        let b = Banco()
        let m = b.modelo()
        let r = m.rutinaReloj()
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

    @Test func otroDiaCambiaElDiaYOtraSemanaSeDescarta() async {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        let a = await receptor.recibir([ev(.serie(diaId: "d2", semana: 5, lugar: "pre-d2-0", indice: 0, reps: 8, kg: 80))], motor: m)
        #expect(a.first?.resultado == .aplicado)
        #expect(m.dia.dia.id == "d2")
        let c = await receptor.recibir([ev(.serie(diaId: "d2", semana: 4, lugar: "pre-d2-0", indice: 0, reps: 8, kg: 80))], motor: m)
        #expect(c.first?.resultado == .descartado)
        let d = await receptor.recibir([ev(.serie(diaId: "d9", semana: 5, lugar: "x", indice: 0, reps: 8, kg: 80))], motor: m)
        #expect(d.first?.resultado == .descartado)
        let e = await receptor.recibir([ev(.serie(diaId: "d2", semana: 5, lugar: "pre-d2-0", indice: 7, reps: 8, kg: 80))], motor: m)
        #expect(e.first?.resultado == .descartado)
    }

    @Test func iniciarArrancaLaSesionYSinMotorNoSeAcusaNada() async {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        let e = ev(.iniciar(diaId: "d1", semana: 5))
        #expect(await receptor.recibir([e], motor: nil).isEmpty, "sin rutina en el teléfono queda en la cola del reloj")
        #expect(await receptor.recibir([e], motor: m) == [AcuseEvento(id: e.id, resultado: .aplicado)])
        #expect(m.inicioSesion != nil)
        #expect(m.iniciadaConBoton)
    }

    @Test func terminarSinRedNoSeAcusaYElRelojLoReintenta() async {
        let b = Banco()
        let m = b.modelo()
        let receptor = ReceptorReloj(disco: b.disco)
        b.servidor.sinRed("iniciar_sesion")
        let serie = ev(.serie(diaId: "d1", semana: 5, lugar: "jal-d1-0", indice: 0, reps: 9, kg: 60))
        let fin = ev(.terminar(diaId: "d1", semana: 5), AHORA + 1)
        let a = await receptor.recibir([fin, serie], motor: m)
        #expect(a.map(\.id) == [serie.id], "en orden de creación: la serie entra; el cierre sin sesión queda para después")
    }
}
