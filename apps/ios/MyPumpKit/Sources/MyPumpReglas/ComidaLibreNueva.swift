import Foundation
import MyPumpModelos

/// "Comida libre" fuera del plan (`openComidaLibreModal` / `guardarComidaLibre`, cliente.html:5345-5440): a mano o
/// con la estimación de la foto del plato. La estimación nunca es exacta, así que los gramos de cada alimento se
/// pueden corregir y los macros se re-escalan en proporción; los totales siguen siendo editables a mano.
public enum ComidaLibreNueva {
    /// Un alimento de la estimación llevado a "por gramo" (`_porGramo`): base para re-escalar.
    public struct Base: Equatable, Sendable {
        public let nombre: String
        /// Los gramos que estimó la IA, redondeados (lo que muestra el campo al abrir).
        public let gramosIniciales: Double
        public let kcal: Double
        public let prot: Double
        public let carb: Double
        public let fat: Double
    }

    public struct Totales: Equatable, Sendable {
        public var kcal: Double
        public var prot: Double
        public var carb: Double
        public var fat: Double
    }

    /// Lo que se manda a `mypump_crear_comida_libre` (más la fecha local, que pone el modelo).
    public struct Datos: Equatable, Sendable {
        public var hora: String?
        public var descripcion: String
        public var kcal: Double
        public var prot: Double
        public var carb: Double
        public var fat: Double
        public var detalle: JSONValue?
    }

    public static func bases(_ e: EstimacionPlato?) -> [Base] {
        (e?.alimentos ?? []).map { a in
            let g = max(1, oCero(a.gramos))
            return Base(nombre: a.nombre ?? "", gramosIniciales: jsRound(oCero(a.gramos)),
                        kcal: oCero(a.kcal) / g, prot: oCero(a.prot) / g, carb: oCero(a.carb) / g, fat: oCero(a.fat) / g)
        }
    }

    /// Los gramos vigentes: lo escrito si es un número ≥ 0, si no los iniciales (`_gramosActuales`).
    public static func gramos(_ bases: [Base], escritos: [Double?]) -> [Double] {
        bases.enumerated().map { i, b in
            if i < escritos.count, let v = escritos[i], v.isFinite, v >= 0 { return v }
            return b.gramosIniciales
        }
    }

    /// `_recalcularDesdeGramos`: kcal enteras, macros con un decimal.
    public static func totales(_ bases: [Base], gramos: [Double]) -> Totales {
        var t = Totales(kcal: 0, prot: 0, carb: 0, fat: 0)
        for (b, g) in zip(bases, gramos) {
            t.kcal += b.kcal * g; t.prot += b.prot * g; t.carb += b.carb * g; t.fat += b.fat * g
        }
        return Totales(kcal: jsRound(t.kcal), prot: r1(t.prot), carb: r1(t.carb), fat: r1(t.fat))
    }

    /// El `detalle` que se guarda: los gramos YA corregidos por el cliente, con sus macros re-escalados.
    public static func detalle(_ bases: [Base], gramos: [Double], confianza: String?, escala: String?) -> JSONValue? {
        guard !bases.isEmpty else { return nil }
        let alimentos: [JSONValue] = zip(bases, gramos).map { b, g in
            .objeto(["nombre": .texto(b.nombre), "gramos": .numero(jsRound(g)), "kcal": .numero(jsRound(b.kcal * g)),
                     "prot": .numero(r1(b.prot * g)), "carb": .numero(r1(b.carb * g)), "fat": .numero(r1(b.fat * g))])
        }
        return .objeto(["alimentos": .lista(alimentos),
                        "confianza": vacioANull(confianza), "escala": vacioANull(escala)])
    }

    /// Al guardar: descripción obligatoria y al menos kcal o un macro. Negativos y vacíos valen 0.
    public static func preparar(descripcion: String, hora: String?, kcal: Double?, prot: Double?, carb: Double?, fat: Double?,
                                detalle: JSONValue?) -> Result<Datos, ErrorFormulario> {
        let d = descripcion.trimmingCharacters(in: .whitespacesAndNewlines)
        func num(_ x: Double?) -> Double { guard let x, x.isFinite, x > 0 else { return 0 }; return x }
        let k = num(kcal), p = num(prot), c = num(carb), f = num(fat)
        guard !d.isEmpty else { return .failure(ErrorFormulario("Contá qué comiste.")) }
        if k <= 0 && p <= 0 && c <= 0 && f <= 0 { return .failure(ErrorFormulario("Cargá al menos las calorías o algún macro.")) }
        return .success(Datos(hora: (hora?.isEmpty ?? true) ? nil : hora, descripcion: d, kcal: k, prot: p, carb: c, fat: f, detalle: detalle))
    }

    /// "HH:MM" de un `Date` en la zona dada (el valor por defecto del campo hora).
    public static func hora(_ d: Date, zona: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func oCero(_ x: Double?) -> Double { guard let x, !x.isNaN else { return 0 }; return x }
    private static func r1(_ v: Double) -> Double { jsRound(v * 10) / 10 }
    private static func vacioANull(_ s: String?) -> JSONValue { (s?.isEmpty ?? true) ? .null : .texto(s!) }
}

/// La fecha local "YYYY-MM-DD" (`hoyLocal()` de la web): el servidor acepta de −7 a +1 días respecto de la suya, así
/// que marcar o registrar no se "corre de día" en otra zona horaria.
public enum FechaLocal {
    public static func hoy(_ ahora: Date = Date(), zona: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.year, .month, .day], from: ahora)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
