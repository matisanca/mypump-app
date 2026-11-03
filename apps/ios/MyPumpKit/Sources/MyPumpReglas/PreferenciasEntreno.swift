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

/// El RIR con el que arranca una serie sin cargar (2.0.3, E4): el objetivo del plan para la semana, así el selector no
/// arranca en 0 (el 48 % de los RIR cargados eran 0, la primera opción). Con un rango («1-2») vale el primer número; con
/// decimales, redondeado hacia arriba; topeado a 5 (el selector va de 0 a 5). Sin objetivo, "" (sin preselección: se
/// guarda null, como siempre). Desvío a propósito de la web, donde el RIR nunca se completa solo (SER-02).
public enum RIRInicial {
    static let numeroRE = RegexWeb(#"\d+([.,]\d+)?"#)

    public static func de(_ objetivo: String?) -> String {
        guard let o = objetivo, let primero = numeroRE.todas(o).first,
              let n = Double(primero.replacingOccurrences(of: ",", with: ".")), n.isFinite else { return "" }
        return String(min(5, max(0, Int(n.rounded(.up)))))
    }
}
