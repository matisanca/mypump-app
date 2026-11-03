import Foundation
import MyPumpModelos
import MyPumpReglas

/// Volumen por músculo (2.1, S2) con lo que ya tiene la app: el historial de Progreso (las filas por clave del ejercicio
/// que se hace, hasta 48 por clave: alcanzan para esta semana y la pasada) y, encima, las series confirmadas en el
/// teléfono que el historial todavía no tiene (puede estar viejo: se trae al abrir Salud), cada una con su fecha real.
/// La regla de conteo y el cruce son del kit (`VolumenMusculo`).
public enum VolumenDatos {
    /// Lo que se sabe de cada clave del plan: el músculo (la cadena de E1) y el tipo del ejercicio que se hace.
    public struct Info: Sendable, Equatable {
        public let musculo: String?
        public let tipo: String?
        public init(musculo: String?, tipo: String?) { self.musculo = musculo; self.tipo = tipo }
    }

    /// Si una clave que ya se vio con el tipo `ya` pasa a tomar el de un lugar nuevo con tipo `nuevo`: solo si el
    /// primero no cuenta (calentamiento o cardio) y el nuevo sí (un lugar de trabajo gana).
    public static func esDeTrabajoMejor(ya: String?, nuevo: String?) -> Bool {
        let noCuenta = { (t: String?) in t.map { VolumenMusculo.tiposQueNoCuentan.contains($0) } ?? false }
        return noCuenta(ya) && !noCuenta(nuevo)
    }

    /// Las filas del historial como registros. Cada fila es una serie distinta (el servidor guarda una por sesión,
    /// ejercicio y número) y cuenta siempre; la clave y el número sirven para no sumar de nuevo lo confirmado en vivo.
    /// Una clave que ya no está en el plan queda sin músculo.
    public static func registros(historial: [String: [RegistroHistorico]], ejercicios: [String: Info],
                                 zona: TimeZone = .current) -> [VolumenMusculo.Registro] {
        historial.keys.sorted().flatMap { clave -> [VolumenMusculo.Registro] in
            let e = ejercicios[clave]
            return (historial[clave] ?? []).map {
                VolumenMusculo.Registro(musculo: e?.musculo, tipo: e?.tipo, fecha: FechaLocal.de($0.registradoEn, zona: zona),
                                        lugar: clave, serie: $0.serie, clave: clave)
            }
        }
    }
}

extension ModeloApp {
    /// El volumen por músculo de esta semana y la pasada. Sin el historial cargado (Salud → Fuerza lo trae), solo lo
    /// confirmado en vivo. Se recalcula solo si cambia lo que lo arma (el historial, la rutina, lo confirmado en el
    /// teléfono, las sustituciones, el catálogo o el día): corre al dibujar Progreso y el cierre del día, y en el cierre
    /// cada tecla de las notas lo pedía de nuevo (revisión del 3-nov).
    public func volumenPorMusculo(zona: TimeZone = .current) -> VolumenMusculo.Resumen {
        let entreno = entreno
        let hoy = FechaLocal.hoy(Date(), zona: zona)
        let firma = [rutina?.id ?? "", "\(versionRutina)", progreso.map { "\(ObjectIdentifier($0).hashValue):\($0.versionHistorial)" } ?? "-",
                     entreno.map { "\(ObjectIdentifier($0).hashValue):\($0.firmaVolumenEnVivo)" } ?? "-", hoy, zona.identifier]
            .joined(separator: "§")
        if let c = cacheVolumen, c.firma == firma { return c.resumen }
        var ejercicios: [String: VolumenDatos.Info] = [:]
        for d in rutina?.estructura.dias ?? [] {
            for b in d.bloques {
                for ex in b.ejercicios {
                    let ef = entreno?.efectivo(ex).ejercicio ?? ex
                    let c = ClaveEjercicio.de(ef.nombre)
                    let clave = c.isEmpty ? ex.id : c
                    // La misma clave como calentamiento y como trabajo: gana el de trabajo, o su historial no contaría.
                    if let ya = ejercicios[clave], !VolumenDatos.esDeTrabajoMejor(ya: ya.tipo, nuevo: ef.tipo) { continue }
                    ejercicios[clave] = VolumenDatos.Info(musculo: entreno?.musculo(ex), tipo: ef.tipo)
                }
            }
        }
        let historial = VolumenDatos.registros(historial: progreso?.historialPorClave ?? [:], ejercicios: ejercicios, zona: zona)
        let r = VolumenMusculo.calcular(historial: historial, enVivo: entreno?.registrosVolumenEnVivo ?? [], hoy: hoy)
        cacheVolumen = (firma, r)
        return r
    }
}
