import Foundation
import MyPumpModelos
import MyPumpReglas

/// Volumen por músculo (2.1, S2) con lo que ya tiene la app: el historial de Progreso (las filas por clave del ejercicio
/// que se hace, hasta 48 por clave: alcanzan para esta semana y la pasada) y, si hoy ya hay series confirmadas en el
/// teléfono, esas en lugar de las del historial de hoy (el historial de hoy puede estar viejo: se trae al abrir Salud).
/// La regla de conteo es la del kit (`VolumenMusculo`).
public enum VolumenDatos {
    /// Lo que se sabe de cada clave del plan: el músculo (la cadena de E1) y el tipo del ejercicio que se hace.
    public struct Info: Sendable, Equatable {
        public let musculo: String?
        public let tipo: String?
        public init(musculo: String?, tipo: String?) { self.musculo = musculo; self.tipo = tipo }
    }

    /// Las filas del historial como registros. Cada fila es una serie distinta (el servidor guarda una por sesión,
    /// ejercicio y número): van sin número, así ninguna se descarta como repetida. Una clave que ya no está en el plan no
    /// se trajo (sin músculo, no se puede asignar).
    public static func registros(historial: [String: [RegistroHistorico]], ejercicios: [String: Info],
                                 zona: TimeZone = .current) -> [VolumenMusculo.Registro] {
        historial.keys.sorted().flatMap { clave -> [VolumenMusculo.Registro] in
            let e = ejercicios[clave]
            return (historial[clave] ?? []).map {
                VolumenMusculo.Registro(musculo: e?.musculo, tipo: e?.tipo, fecha: FechaLocal.de($0.registradoEn, zona: zona),
                                        lugar: clave, serie: nil)
            }
        }
    }
}

extension ModeloApp {
    /// El volumen por músculo de esta semana y la pasada. Sin el historial cargado (Salud → Fuerza lo trae), solo lo de
    /// hoy en vivo.
    public func volumenPorMusculo(zona: TimeZone = .current) -> VolumenMusculo.Resumen {
        let entreno = entreno
        var ejercicios: [String: VolumenDatos.Info] = [:]
        for d in rutina?.estructura.dias ?? [] {
            for b in d.bloques {
                for ex in b.ejercicios {
                    let ef = entreno?.efectivo(ex).ejercicio ?? ex
                    let c = ClaveEjercicio.de(ef.nombre)
                    let clave = c.isEmpty ? ex.id : c
                    if ejercicios[clave] == nil {
                        ejercicios[clave] = VolumenDatos.Info(musculo: entreno?.musculo(ex), tipo: ef.tipo)
                    }
                }
            }
        }
        let historial = VolumenDatos.registros(historial: progreso?.historialPorClave ?? [:], ejercicios: ejercicios, zona: zona)
        let vivo = entreno?.registrosVolumenHoy ?? []
        return VolumenMusculo.calcular(historial: historial, hoyEnVivo: vivo.isEmpty ? nil : vivo, hoy: FechaLocal.hoy(Date(), zona: zona))
    }
}
