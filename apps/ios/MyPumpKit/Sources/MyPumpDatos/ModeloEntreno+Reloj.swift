import Foundation
import MyPumpModelos
import MyPumpReglas
import MyPumpReloj

/// El Apple Watch visto desde el motor de Entreno (tanda 3, 2.2): la rutina del día para el reloj y los eventos del reloj
/// aplicados por el mismo camino que un toque en la pantalla (así van a la cola de siempre, con su sesión, su descanso y
/// su récord). El iPhone es el único que habla con el servidor.
extension ModeloEntreno {
    /// La rutina del día como la ve el reloj: lo mismo que pintan las cards (lo sugerido de cada serie, el descanso, la
    /// preparación del plan o los datos para que el reloj la arme con el kit, y las marcas para el récord).
    public func rutinaReloj() -> RutinaReloj {
        let hoy = FechaJS.ymd(reloj(), zona: zona)
        let ejercicios: [EjercicioReloj] = dia.lista.map { plan in
            let lugar = plan.id
            let ef = efectivo(plan).ejercicio
            let conEquipo = hecho(plan)
            let sinKg = ReglasEjercicio.sinKg(ef)
            let local = dia.ejercicios[lugar]?.series ?? []
            let series: [SerieReloj] = local.indices.map { i in
                let s = local[i]
                let f = dia.fila(lugar, i, efectivo: ef)
                return SerieReloj(numero: i + 1, repsSugeridas: Self.entero(f?.placeholderReps),
                                  kgSugerido: sinKg ? nil : Self.numero(f?.placeholderKg),
                                  confirmada: s.confirmada, reps: s.confirmada ? Self.entero(s.reps) : nil,
                                  kg: s.confirmada && !sinKg ? Self.numero(s.kg) : nil)
            }
            let historial = dia.historial[lugar] ?? []
            return EjercicioReloj(
                lugar: lugar, nombre: conEquipo.nombre, bloque: nil, tipo: ef.tipo, musculo: musculo(plan), equipo: conEquipo.equipo,
                sinKg: sinKg, sinPeso: ReglasEjercicio.esSinPeso(nombre: ef.nombre, tipo: ef.tipo, equipo: ef.equipo),
                aproximacionesPlan: conEquipo.aproximaciones?.map(AproximacionReloj.init),
                descansoSegundos: dia.descanso(lugar), repsPlan: Progresiones.pauta(ef, semana: semana).reps,
                estado: dia.estado(lugar), series: series,
                anteriores: RecordSerie.anteriores(historial, hoy: hoy, zona: zona).map(MarcaReloj.init),
                historiaSuficiente: RecordSerie.historiaSuficiente(historial, hoy: hoy, zona: zona))
        }
        return RutinaReloj(rutinaId: rutina.id, diaId: dia.dia.id ?? "", semana: semana, nombreDia: dia.dia.nombre ?? "",
                           fecha: hoy, generada: ahoraMs, ejercicios: ejercicios, inicioSesion: inicioSesion,
                           diaFinalizado: dia.diaFinalizado, proximo: proximoEntreno(), descanso: descanso.descanso?.guardado, demo: demo)
    }

    /// El próximo día que falta en la semana (después del que se mira, dando la vuelta).
    func proximoEntreno() -> ProximoEntreno? {
        guard let i = dias.firstIndex(where: { $0.id == dia.dia.id }), dias.count > 1 else { return nil }
        let orden = dias[(i + 1)...] + dias[..<i]
        guard let d = orden.first(where: { !hecho($0) }) ?? orden.first, let id = d.id else { return nil }
        return ProximoEntreno(diaId: id, nombre: d.nombre ?? "", ejercicios: d.bloques.reduce(0) { $0 + $1.ejercicios.count })
    }

    static func entero(_ s: String?) -> Int? {
        guard let s, let v = JS.parseInt(s), v.isFinite, v >= 1 else { return nil }
        return Int(v)
    }

    static func numero(_ s: String?) -> Double? {
        guard let s, let v = JS.parseFloat(s.replacingOccurrences(of: ",", with: ".")), v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// Aplica un evento del reloj. nil = no se pudo ahora (sin red al cerrar): el reloj lo vuelve a mandar.
    public func aplicarEventoReloj(_ e: EventoReloj) async -> (AcuseEvento.Resultado, String?)? {
        guard e.semana == semana else { return (.descartado, "Es de otra semana") }
        if e.diaId != dia.dia.id {
            guard dias.contains(where: { $0.id == e.diaId }) else { return (.descartado, "El día ya no está en la rutina") }
            await cambiarDia(e.diaId)
            guard dia.dia.id == e.diaId else { return nil }
        }
        switch e {
        case .iniciar:
            await empezar()
            return (.aplicado, nil)
        case .serie(_, _, let lugar, let i, let reps, let kg):
            guard let ej = dia.ejercicios[lugar], i >= 0, i < ej.series.count else { return (.descartado, "La serie ya no está") }
            let s = ej.series[i]
            let kgTexto = kg.map { JS.texto($0) } ?? ""
            if s.confirmada {
                if Self.entero(s.reps) == reps && (kg == nil || Self.numero(s.kg) == kg) { return (.aplicado, nil) }
                await editarSerie(lugar, i)
            }
            escribir(lugar, i, campo: "reps", valor: String(reps))
            if kg != nil { escribir(lugar, i, campo: "kg", valor: kgTexto) }
            // Lo confirmó en el reloj: «¿está bien cargado?» y «reabrir el día» se contestan que sí.
            await confirmarSerie(lugar, i) { _ in true }
            return dia.ejercicios[lugar]?.series[i].confirmada == true ? (.aplicado, nil) : (.descartado, "No se pudo registrar")
        case .terminar:
            // Sin nada hecho no hay qué cerrar; con algo hecho (aunque la sesión todavía no exista: sin red) se intenta.
            guard cierreHabilitado || inicioSesion != nil, !dia.diaFinalizado else { return (.aplicado, nil) }
            switch await cerrarDia(notas: "") {
            case .cerrado, .demo: return (.aplicado, nil)
            case .sinSesion, .fallo: return nil
            }
        }
    }
}

/// Recibe los eventos del reloj en el iPhone: descarta los repetidos por id (guardados en el disco de la cuenta) y aplica
/// el resto en orden sobre el motor de Entreno. Devuelve los acuses para el reloj.
@MainActor
public final class ReceptorReloj {
    public static let archivo = "reloj-aplicados.json"
    private let disco: Disco?
    private var aplicados: AplicadosReloj

    public init(disco: Disco?) {
        self.disco = disco
        aplicados = disco?.leer(AplicadosReloj.self, Self.archivo) ?? AplicadosReloj()
    }

    public func recibir(_ eventos: [EventoEnCola], motor: ModeloEntreno?) async -> [AcuseEvento] {
        var acuses: [AcuseEvento] = []
        for e in eventos.sorted(by: { $0.creado < $1.creado }) {
            if aplicados.contiene(e.id) {
                acuses.append(AcuseEvento(id: e.id, resultado: .repetido))
                continue
            }
            guard let motor else { break }
            guard let (resultado, motivo) = await motor.aplicarEventoReloj(e.evento) else { break }
            aplicados.anotar(e.id)
            _ = disco?.guardar(aplicados, Self.archivo)
            acuses.append(AcuseEvento(id: e.id, resultado: resultado, motivo: motivo))
        }
        return acuses
    }
}

extension ReceptorReloj {
    /// Con el disco de la cuenta del motor: los aplicados son de la cuenta, como la cola.
    public convenience init(motor: ModeloEntreno) { self.init(disco: motor.disco) }
}
