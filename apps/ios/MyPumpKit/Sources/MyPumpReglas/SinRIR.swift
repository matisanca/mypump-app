import Foundation

/// REGLA DURA (Mati): «RIR» y «reps en reserva» no aparecen NUNCA en una pantalla del alumno; todo va al fallo.
///
/// El texto libre del plan que se dibuja tal cual (`notas_tecnica`, la nota de una serie de preparación) pasa por acá:
/// se saca la mención sin romper la frase y, si queda alguna que no se entiende, se saca la oración entera. «cerca del
/// fallo» pasa a «al fallo». Excepción: el plan con reserva a propósito (decisión clínica de Mati: lumbar, cardiopatía,
/// excepciones): si el rir de esa semana tiene un número mayor que 0, la nota es una indicación clínica y va entera.
///
/// Port exacto de `sinRIR` / `notaParaAlumno` de la web (`public/js/reglas-entreno.js`, rama nativa-web-231-llamadas);
/// vectores en `apps/shared/vectores/sin_rir.json`, que corre también Android.
public enum TextoAlumno {
    private static func re(_ p: String) -> NSRegularExpression {
        do { return try NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        catch { preconditionFailure("regex de sinRIR inválida: \(p) → \(error)") }
    }

    private static let n = #"\d+(?:[.,]\d+)?(?:\s*(?:[-–]|a|o)\s*\d+(?:[.,]\d+)?)?"#
    private static let res = #"(?:en reserva|en la recámara|en el tanque)"#
    private static let reps = #"(?:repeticiones|repes|reps|rep)"#
    private static let detecta = re(#"\bRIR\b|en reserva|en la recámara|en el tanque|cerca del fallo"#)
    private static let queda = re(#"\bRIR\b|en reserva|en la recámara|en el tanque"#)

    nonisolated(unsafe) private static let pasos: [(NSRegularExpression, String)] = [
        (re(#"\bcerca del fallo\b"#), "al fallo"),
        (re(#"\bno calcules\s+(?:el\s+)?RIR\b\s*[:.,;]?\s*"#), ""),
        (re(#",\s*([^\s,.;:()]+(?:\s+[^\s,.;:()]+)?)\s+y\s+(?:con\s+)?RIR\s*"# + n), " y $1"),
        (re(#"\s*[·,;]\s*(?:con\s+)?RIR\s*"# + n), ""),
        (re(#"\s+y\s+(?:con\s+)?RIR\s*"# + n), ""),
        (re(#"\s*\([^()]*(?:\bRIR\b|en reserva|en la recámara|en el tanque|te sobra|que te queden|quedar\s+\d)[^()]*\)"#), ""),
        (re(#"\s*\b(?:con\s+)?RIR\s*"# + n), ""),
        (re(#"(?:\s+y\s+|\s*,\s*)?\b(?:dejá|deja|quedate con)\s+"# + n + #"\s*"# + reps + #"?\s*"# + res + #"(?:\s+en todo)?\s*(?:y\s+|,\s*)?"#), " "),
        (re(#"\s*,?\s*(?:\by\s+)?(?:solo\s+)?(?:\b(?:dejando|dejar|con|que te queden?)\s+)?(?:solo\s+)?"# + n + #"\s*"# + reps + #"?\s*"# + res + #"(?:\s+en todo)?"#), ""),
    ]
    nonisolated(unsafe) private static let limpieza: [(NSRegularExpression, String)] = [
        (re(#"[ \t]{2,}"#), " "),
        (re(#"\(\s*\)"#), ""),
        (re(#"\s+([,.;:)])"#), "$1"),
        (re(#"\(\s+"#), "("),
        (re(#"[,;:]\s*([.!?])"#), "$1"),
        (re(#"([,;:])\s*[,;:]"#), "$1"),
        (re(#"\s*[·—–]\s*([.!?)]|$)"#), "$1"),
    ]
    private static let corteOracion = re(#"(?<=[.!?])\s+"#)
    private static let inicioSucio = re(#"^[\s,;:·—–-]+"#)
    private static let soloPuntos = re(#"^[.!?]+$"#)

    private static func prueba(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    private static func reemplazar(_ r: NSRegularExpression, _ s: String, _ por: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: por)
    }

    private static func oracion(_ o: String) -> String {
        let x = reemplazar(inicioSucio, o, "").trimmingCharacters(in: .whitespaces)
        if x.isEmpty || prueba(soloPuntos, x) || prueba(queda, x) { return "" }
        return x.prefix(1).uppercased() + x.dropFirst()
    }

    private static func linea(_ l: String) -> String {
        var x = l
        for (r, por) in pasos { x = reemplazar(r, x, por) }
        for (r, por) in limpieza { x = reemplazar(r, x, por) }
        let marca = "\u{1F}"
        return reemplazar(corteOracion, x, marca).components(separatedBy: marca)
            .map(oracion).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// El texto sin RIR ni reps en reserva. Lo que no los menciona vuelve igual.
    public static func sinRIR(_ texto: String) -> String {
        guard prueba(detecta, texto) else { return texto }
        var lineas: [String] = []
        for l in texto.components(separatedBy: "\n") {
            if !prueba(detecta, l) { lineas.append(l); continue }
            let r = linea(l)
            if !r.isEmpty { lineas.append(r) }
        }
        return lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func sinRIR(_ texto: String?) -> String? { texto.map { sinRIR($0) } }

    /// ¿El rir del plan de esa semana pide reserva? Un número mayor que 0 (sin dato, 0, «al fallo» o RPE: no).
    public static func conReserva(_ rir: String?) -> Bool {
        guard let o = rir, !RIRDelPlan.rpeRE.prueba(o), let rango = RIRDelPlan.rangoRE.todas(o).first else { return false }
        return RIRDelPlan.numeroRE.todas(rango).contains { (Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0 }
    }

    /// La nota del plan como la ve el alumno: entera si esa semana lleva reserva clínica; si no, sin RIR. Vacía → nil.
    public static func notaParaAlumno(_ texto: String?, rir: String?) -> String? {
        guard let t = texto else { return nil }
        let r = (conReserva(rir) ? t : sinRIR(t)).trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? nil : r
    }
}
