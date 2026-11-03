import Foundation
import MyPumpModelos
import MyPumpReglas

/// La rutina del día que el iPhone le manda al reloj: lo justo para entrenar sin el teléfono. El iPhone la arma con su
/// motor (`ModeloEntreno.rutinaReloj()`), así lo sugerido, el descanso, la preparación y el récord salen de las mismas
/// reglas que la pantalla del teléfono; el reloj vuelve a correr esas reglas del kit (`Preparacion`, `RecordSerie`,
/// `Descanso`) cuando el alumno cambia el kg con la corona.
public struct RutinaReloj: Codable, Equatable, Sendable {
    public var rutinaId: String
    public var diaId: String
    public var semana: Int
    /// «Tirón A — ancho»
    public var nombreDia: String
    /// YYYY-MM-DD local del teléfono cuando se armó: una rutina de otro día no se usa para registrar.
    public var fecha: String
    /// ms: cuándo se armó (la más nueva gana).
    public var generada: Double
    public var ejercicios: [EjercicioReloj]
    /// ms: el arranque de la sesión en el teléfono, si ya empezó.
    public var inicioSesion: Double?
    public var diaFinalizado: Bool
    /// El próximo entreno (para la complicación), si el día de hoy ya está hecho o no hay rutina para hoy.
    public var proximo: ProximoEntreno?
    /// El descanso que corre en el teléfono (para seguirlo en el reloj).
    public var descanso: Descanso.Guardado?
    public var demo: Bool

    public init(rutinaId: String, diaId: String, semana: Int, nombreDia: String, fecha: String, generada: Double,
                ejercicios: [EjercicioReloj], inicioSesion: Double? = nil, diaFinalizado: Bool = false,
                proximo: ProximoEntreno? = nil, descanso: Descanso.Guardado? = nil, demo: Bool = false) {
        self.rutinaId = rutinaId; self.diaId = diaId; self.semana = semana; self.nombreDia = nombreDia; self.fecha = fecha
        self.generada = generada; self.ejercicios = ejercicios; self.inicioSesion = inicioSesion
        self.diaFinalizado = diaFinalizado; self.proximo = proximo; self.descanso = descanso; self.demo = demo
    }

    /// Las entradas del día para `Preparacion.series` (el orden del día, con los sustitutos).
    public var entradasPreparacion: [Preparacion.Entrada] { ejercicios.map(\.entrada) }
}

public struct ProximoEntreno: Codable, Equatable, Sendable {
    public var diaId: String
    public var nombre: String
    public var ejercicios: Int
    public init(diaId: String, nombre: String, ejercicios: Int) { self.diaId = diaId; self.nombre = nombre; self.ejercicios = ejercicios }
}

/// Un ejercicio del día visto desde el reloj.
public struct EjercicioReloj: Codable, Equatable, Sendable {
    /// El id del lugar en el día (`slug-dN-idx`): con él el iPhone sabe qué card es.
    public var lugar: String
    /// El nombre del que se hace (el sustituto, si hay).
    public var nombre: String
    public var bloque: String?
    /// "compuesto", "aislamiento", "calentamiento", "cardio"…
    public var tipo: String?
    public var musculo: String?
    public var equipo: String?
    /// De peso corporal: no lleva kg.
    public var sinKg: Bool
    /// `ReglasEjercicio.esSinPeso` (para la preparación).
    public var sinPeso: Bool
    /// La preparación del plan (`aproximaciones`), si la trae; nil = la arma la app.
    public var aproximacionesPlan: [AproximacionReloj]?
    /// El descanso en segundos (el elegido a mano, si hay, o el del plan).
    public var descansoSegundos: Int
    /// "8-10"
    public var repsPlan: String?
    /// "pendiente", "en_curso", "completo", "completo_sin_datos"…
    public var estado: String
    public var series: [SerieReloj]
    /// Las marcas de días anteriores (para el récord, `RecordSerie.anteriores`); vacío = sin historia.
    public var anteriores: [MarcaReloj]
    /// `RecordSerie.historiaSuficiente`: si es false, no se avisa récord.
    public var historiaSuficiente: Bool

    public init(lugar: String, nombre: String, bloque: String? = nil, tipo: String?, musculo: String?, equipo: String?,
                sinKg: Bool, sinPeso: Bool = false, aproximacionesPlan: [AproximacionReloj]? = nil, descansoSegundos: Int,
                repsPlan: String?, estado: String = "pendiente", series: [SerieReloj], anteriores: [MarcaReloj] = [],
                historiaSuficiente: Bool = true) {
        self.lugar = lugar; self.nombre = nombre; self.bloque = bloque; self.tipo = tipo; self.musculo = musculo
        self.equipo = equipo; self.sinKg = sinKg; self.sinPeso = sinPeso; self.aproximacionesPlan = aproximacionesPlan
        self.descansoSegundos = descansoSegundos; self.repsPlan = repsPlan; self.estado = estado; self.series = series
        self.anteriores = anteriores; self.historiaSuficiente = historiaSuficiente
    }

    public var entrada: Preparacion.Entrada { Preparacion.Entrada(tipo: tipo, musculo: musculo, nombre: nombre, sinPeso: sinPeso) }
    public var confirmadas: Int { series.filter(\.confirmada).count }
    public var terminado: Bool { EstadosEjercicio.terminales.contains(estado) || (!series.isEmpty && confirmadas == series.count) }
    /// El índice de la primera serie sin confirmar.
    public var proximaSerie: Int? { series.firstIndex { !$0.confirmada } }
    /// Con qué se carga (decide el paso de la corona).
    public var equipoCarga: Preparacion.Equipo { Preparacion.equipo(nombre: nombre, equipo: equipo) }
}

public struct AproximacionReloj: Codable, Equatable, Sendable {
    public var reps: String?
    public var pct: Double?
    public var kg: Double?
    public var nota: String?
    public init(reps: String? = nil, pct: Double? = nil, kg: Double? = nil, nota: String? = nil) {
        self.reps = reps; self.pct = pct; self.kg = kg; self.nota = nota
    }
    public init(_ a: Aproximacion) { self.init(reps: a.reps, pct: a.pct, kg: a.kg, nota: a.nota) }
    public var aproximacion: Aproximacion { Aproximacion(reps: reps, pct: pct, kg: kg, nota: nota) }
}

/// Una serie efectiva. Lo sugerido viene armado por el teléfono (lo de la última vez, o lo heredado de la serie de
/// arriba); lo hecho, si ya se confirmó (en el teléfono o en el reloj).
public struct SerieReloj: Codable, Equatable, Sendable {
    public var numero: Int
    public var repsSugeridas: Int?
    public var kgSugerido: Double?
    public var confirmada: Bool
    public var reps: Int?
    public var kg: Double?
    public init(numero: Int, repsSugeridas: Int? = nil, kgSugerido: Double? = nil, confirmada: Bool = false, reps: Int? = nil, kg: Double? = nil) {
        self.numero = numero; self.repsSugeridas = repsSugeridas; self.kgSugerido = kgSugerido
        self.confirmada = confirmada; self.reps = reps; self.kg = kg
    }
}

public struct MarcaReloj: Codable, Equatable, Sendable {
    public var kg: Double
    public var reps: Int
    public init(kg: Double, reps: Int) { self.kg = kg; self.reps = reps }
    public init(_ m: RecordSerie.Marca) { self.init(kg: m.kg, reps: m.reps) }
    public var marca: RecordSerie.Marca { RecordSerie.Marca(kg: kg, reps: reps) }
}
