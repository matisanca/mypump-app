import Foundation

/// El descanso elegido a mano para un ejercicio (2.0.3, E2): tocar el descanso del ejercicio abre un selector de 0:30 a
/// 5:00 en pasos de 15 s. Lo elegido vive en el teléfono, por la clave del ejercicio que se hace (`ClaveEjercicio`), y le
/// gana al `descanso_segundos` del plan. Lo verifican los vectores de `apps/shared/vectores/entreno_203.json`.
public enum DescansoPropio {
    public static let minimo = 30
    public static let maximo = 300
    public static let paso = 15

    /// 0:30, 0:45 … 5:00.
    public static let opciones: [Int] = Array(stride(from: minimo, through: maximo, by: paso))

    /// Lo elegido vale si es una de las opciones (un archivo viejo o tocado no mete un descanso de 0 ni de una hora).
    public static func valido(_ s: Int?) -> Int? {
        guard let s, opciones.contains(s) else { return nil }
        return s
    }

    /// El descanso que se usa: el propio si hay, si no el del plan (que `normalizarRutina` ya completó con 90).
    public static func segundos(propio: Int?, plan: Int?) -> Int {
        valido(propio) ?? plan ?? NormalizacionRutina.descansoPorDefecto
    }
}

/// El RIR que se guarda sin preguntarlo (2.0.3): las series efectivas van al fallo y la app ya no muestra el RIR, pero
/// la recuperación cuenta las «series duras» con `rir_real` ≤ 2 (todo null la apaga). Al confirmar se guarda el
/// objetivo del plan para la semana: el primer número del rango (redondeado hacia arriba, entre 0 y 5); sin objetivo o
/// sin número, 0 (al fallo). Debajo de «Series efectivas» va la leyenda: «Al fallo» o «Dejando 1–2 en reserva» con el
/// rango del plan. Lo verifican los vectores de `apps/shared/vectores/entreno_203.json` (sección `rir`).
public enum RIRDelPlan {
    static let numeroRE = RegexWeb(#"\d+([.,]\d+)?"#)
    static let rangoRE = RegexWeb(#"\d+([.,]\d+)?(\s*[-–]\s*\d+([.,]\d+)?)?"#)

    /// Lo que se guarda en `rir_real` (como texto, igual que lo que se elegía en el selector).
    public static func guardar(_ objetivo: String?) -> String {
        guard let o = objetivo, let primero = numeroRE.todas(o).first,
              let n = Double(primero.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return "0" }
        return String(min(5, max(0, Int(n.rounded(.up)))))
    }

    /// «Al fallo» (objetivo 0 o sin objetivo) o «Dejando 1–2 en reserva».
    public static func leyenda(_ objetivo: String?) -> String {
        guard let o = objetivo, let rango = rangoRE.todas(o).first else { return "Al fallo" }
        let numeros = numeroRE.todas(rango).compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        if numeros.allSatisfy({ $0 == 0 }) { return "Al fallo" }
        let partes = rango.split(whereSeparator: { $0 == "-" || $0 == "–" })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: ",") }
        return "Dejando \(partes.joined(separator: "–")) en reserva"
    }
}
