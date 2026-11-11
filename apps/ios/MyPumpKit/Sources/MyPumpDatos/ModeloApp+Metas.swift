import Foundation
import MyPumpModelos
import MyPumpReglas

/// Metas de pasos y ritmo de peso (2.3.0, propuesta 8). Todo detrás de la palanca `metas_pasos`: apagada, la app es la de
/// siempre. Las metas salen de la dieta publicada; los pasos, de Salud (lo que la app ya sincroniza, sin permisos nuevos).
extension ModeloApp {
    /// Las metas del plan, o nil con la palanca apagada o sin ninguna meta (planes viejos: no se inventa nada).
    public var metas: MetasPlan? {
        // La demo trae las suyas (`historial.json`), sin palanca: nada de esto sale de una cuenta.
        if esDemo { return demoHistorial?.metas }
        guard palanca.metasPasos, let e = dieta?.estructura else { return nil }
        let m = MetasPlan(e)
        return m.vacio ? nil : m
    }

    /// El «Pump del día» de hoy con los pasos de Salud. nil sin meta de pasos. `conectado` dice si hay de dónde sacarlos.
    public func pumpDelDia(hoy: String = FechaLocal.hoy()) -> (vista: PumpDelDia.Vista, conectado: Bool)? {
        guard let meta = metas?.metaPasos else { return nil }
        let filas = esDemo ? (demoHistorial?.salud ?? []) : (salud?.salud ?? [])
        let p = PumpDelDia.pasosPorDia(filas)
        guard let v = PumpDelDia.vista(pasosPorDia: p, meta: meta, hoy: hoy) else { return nil }
        // Conectado: Salud sincroniza desde este teléfono, o llegaron pasos de otro lado (otro teléfono, un reloj) esta semana.
        let conectado = esDemo || salud?.conectado == true || SaludVista.tieneReciente(filas, tipos: ["pasos"], dias: 7, hoy: hoy)
        return (v, conectado)
    }

    /// ¿Toca la celebración ahora? Una sola vez por día y por cuenta.
    public func debeCelebrarPump(_ v: PumpDelDia.Vista, hoy: String = FechaLocal.hoy()) -> Bool {
        PumpDelDia.debeCelebrar(registroMetas, hoy: hoy, pasosHoy: v.pasosHoy, meta: v.meta)
    }

    /// Anota el día como celebrado (se llama apenas empieza la animación o sale el aviso, para que no se repita).
    public func marcarPumpCelebrado(hoy: String = FechaLocal.hoy()) {
        registroMetas = PumpDelDia.marcar(registroMetas, hoy: hoy)
        _ = disco?.guardar(registroMetas, "metas.json")
    }
}
