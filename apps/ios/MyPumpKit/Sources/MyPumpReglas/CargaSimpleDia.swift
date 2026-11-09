import Foundation
import MyPumpModelos

/// La carga simple dentro del día en curso (2.3.0). Las series siguen siendo las de `ejercicios[id].series` y salen por la
/// cola de siempre; la carga única vive aparte, en `cargas`, hasta que un OK la baja a la serie.
extension DiaEnCurso {
    /// Lo de afuera que hace falta para armar la carga de un lugar.
    public struct ContextoCarga: Sendable {
        public let efectivo: Ejercicio
        public let equipo: Preparacion.Equipo
        public let mensajeSemana: String?
        /// YYYY-MM-DD local de hoy.
        public let hoy: String
        public init(efectivo: Ejercicio, equipo: Preparacion.Equipo, mensajeSemana: String?, hoy: String) {
            self.efectivo = efectivo; self.equipo = equipo; self.mensajeSemana = mensajeSemana; self.hoy = hoy
        }
    }

    public func claveAumento(_ id: String) -> String { "\(ClaveEjercicio.de(nombreEfectivo(id)))|\(semana)" }

    /// La carga del lugar como se ve ahora.
    public func cargaSimple(_ id: String, contexto c: ContextoCarga) -> CargaSimple? {
        guard let e = ejercicios[id] else { return nil }
        let (v, d) = varianteActiva(id)
        let h = historial[id] ?? []
        let refs = HistorialEntreno.ultimaSesion(h, variante: v, esDefault: d, antesDe: c.hoy, zona: zona)
        let sinKg = ReglasEjercicio.sinKg(c.efectivo)
        func armar(_ estado: CargaSimple.Estado?) -> CargaSimple {
            var s = CargaSimple(ejercicio: c.efectivo, semana: semana, ultimaVez: refs, equipo: c.equipo, sinKg: sinKg,
                                recordKg: HistorialEntreno.recordKg(h), mensajeSemana: c.mensajeSemana, seriesLocales: e.series,
                                estado: estado, yaAumentadoEstaSemana: aumentosSemana.contains(claveAumento(id)))
            s.varianteActual = variantesVisibles(id) == nil ? nil : JS.verdadero(e.variante)
            return s
        }
        guard var estado = cargas[id] else { return armar(nil) }
        // Se tocó algo antes de que llegara el historial (sin base): cuando llega, la carga no puede quedar vacía.
        if estado.carga == nil, estado.cargaUltimaVez == nil, estado.aumento == .noCorresponde {
            let base = armar(nil)
            estado.carga = base.carga
            estado.cargaUltimaVez = base.cargaUltimaVez
            estado.aumento = base.aumento
        }
        return armar(estado)
    }

    /// Una acción sobre la carga (subir, aceptar, marcar reps…): guarda el estado resultante.
    public mutating func cambiarCarga(_ id: String, contexto c: ContextoCarga, _ accion: (inout CargaSimple) -> Void) {
        guard var s = cargaSimple(id, contexto: c) else { return }
        accion(&s)
        cargas[id] = s.estado
        switch s.aumento {
        case .aceptado, .descartado: aumentosSemana.insert(claveAumento(id))
        default: break
        }
    }

    /// Una corrección de una serie ya hecha: nunca la desconfirma, así no queda en un limbo sin registrar. Reescribe esa
    /// serie con la misma clave de cola y, sin cambios, no escribe nada.
    public enum Correccion: Equatable, Sendable {
        case sinCambios
        case guardada([Efecto])
        case rechazada(String)
        case preguntar(Pregunta)
        case faltanDatos
    }

    public mutating func corregirSerie(_ id: String, _ idx: Int, reps: Int, kg: Double?, efectivo: Ejercicio? = nil, registrarIgual: Bool? = nil) -> Correccion {
        guard let e = ejercicios[id], idx >= 0, idx < e.series.count, e.series[idx].confirmada, let ex = ejercicio(id) else { return .faltanDatos }
        let s = e.series[idx]
        let propia = esDelEjercicioActual(id, s)
        var deLaSerie = efectivo ?? ex
        if !propia, let n = JS.verdadero(s.nombreRegistrado) { deLaSerie = ex; deLaSerie.nombre = n }
        let sinKg = ReglasEjercicio.sinKg(deLaSerie) && (propia || s.kg.isEmpty)
        guard sinKg || kg != nil else { return .faltanDatos }
        let repsTexto = String(reps), kgTexto = sinKg ? "" : kg.map(JS.texto) ?? ""
        if repsTexto == s.reps && kgTexto == s.kg { return .sinCambios }
        let prog = Progresiones.pauta(deLaSerie, semana: semana)
        switch Verosimilitud.evaluar(reps: repsTexto, kg: kgTexto, sinKg: sinKg, recordKg: propia ? HistorialEntreno.recordKg(historial[id] ?? []) : 0,
                                     repsUltimaVez: propia ? repsUltimaVez(id, idx) : "", repsPlan: prog.reps) {
        case .ok: break
        case .rechazada(let aviso): return .rechazada(aviso)
        case .preguntar(let p):
            guard registrarIgual == true else { return registrarIgual == false ? .sinCambios : .preguntar(p) }
        }
        ejercicios[id]!.series[idx].reps = repsTexto
        ejercicios[id]!.series[idx].kg = kgTexto
        ejercicios[id]!.series[idx].aviso = nil
        return .guardada(escribirSerie(id, idx))
    }
}
