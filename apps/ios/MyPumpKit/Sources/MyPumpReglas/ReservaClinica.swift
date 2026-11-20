import Foundation
import MyPumpModelos

/// Reserva clínica (19/11, OK de Mati). Todo va al fallo, salvo el plan que deja reps en reserva a propósito
/// (cardiopatía, lumbar, competencia: lo decide Mati y el servidor lo publica en el rir de la pauta). Con reserva clínica
/// la app NUNCA dice «Al fallo», «llevá al fallo» ni «Subí la carga», no sugiere subir y en lugar de la nota automática
/// de progresión muestra la pauta del plan. Sin reserva, todo igual.
///
/// Fuente única: el rir de cada semana de la progresión (`Pauta.rir`), el mismo campo que ya lee
/// `TextoAlumno.conReserva`, con dos diferencias a propósito:
/// - cuenta solo un rango sin el 0 («2-3», «1-2», «3»): «0-1» deja llegar al fallo y es el de los planes viejos y de la
///   semana 1 del generador;
/// - es del alumno, no del ejercicio: alcanza un ejercicio con reserva en la semana que se muestra o en una posterior (el
///   taper con rir vacío entre semanas con reserva no vuelve al fallo, ni los ejercicios sin rir de ese plan). Las semanas
///   ya pasadas no cuentan: son las rampas viejas de las semanas 1 a 3.
///
/// La demo no es el plan de un alumno: queda como siempre (lo resuelve `ModeloEntreno.reservaClinica`).
/// Gemelos: `reservaIndicada`/`reservaClinicaDelPlan`/`notaReserva` de `public/js/reglas-entreno.js` (web) y
/// `ReservaClinica.kt`. Vectores: `apps/shared/vectores/reserva_clinica.json`.
public enum ReservaClinica {
    /// ¿Este rir pide reserva? Todos los números del primer rango mayores que 0 («2-3», «3», «1,5-2»), y no es RPE.
    /// «0-1», «0», «al fallo», sin dato o un RPE: no.
    public static func indicada(_ rir: String?) -> Bool {
        guard let o = rir, !RIRDelPlan.rpeRE.prueba(o), let rango = RIRDelPlan.rangoRE.todas(o).first else { return false }
        let numeros = RIRDelPlan.numeroRE.todas(rango).compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        return !numeros.isEmpty && numeros.allSatisfy { $0 > 0 }
    }

    /// ¿El plan tiene reserva clínica en la semana que se muestra o en una posterior? `dias`: todos los del plan. La
    /// semana se acota como `Progresiones.pauta` (pasada la última, la última); sin progresión, `rir_objetivo ?? rir`.
    public static func delPlan(_ dias: [Dia], semana: Int?) -> Bool {
        let sem = Progresiones.semanaJS(semana)
        for d in dias {
            for b in d.bloques {
                for e in b.ejercicios {
                    if !e.progresion.isEmpty {
                        let desde = max(0, min(sem - 1, e.progresion.count - 1))
                        if e.progresion[desde...].contains(where: { indicada($0.rir) }) { return true }
                    } else if indicada(e.rirObjetivo ?? e.rirSuelto) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// La leyenda debajo de «Series efectivas» con reserva: la de esa semana («Dejando 2–3 en reserva»); sin número,
    /// ninguna. Nunca «Al fallo».
    public static func leyenda(_ rir: String?) -> String? {
        let l = RIRDelPlan.leyenda(rir)
        return l == "Al fallo" ? nil : l
    }

    /// La leyenda dentro de una frase: « dejando 2–3 en reserva»; sin leyenda, nada.
    static func frase(_ l: String?) -> String {
        guard let l else { return "" }
        return " " + (l == "Al fallo" ? "al fallo" : l.prefix(1).lowercased() + l.dropFirst())
    }

    /// En lugar de la nota automática de progresión, la pauta del plan: «Seguí la pauta de esta semana (3×10), dejando
    /// 2–3 en reserva.». Una pauta sin números («No va esta semana») va tal cual. Nunca `cambia` (sin cartel de cambio);
    /// `calibracion` es la semana sin anterior, como en `Progresiones.nota`.
    public static func nota(_ p: Progresion, calibracion: Bool) -> NotaProgresion {
        let reps = p.reps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let texto: String
        if let r = reps, p.series == nil, !r.contains(where: { $0.isASCII && $0.isNumber }) {
            let fin = r.hasSuffix(".") || r.hasSuffix("!") || r.hasSuffix("?") ? "" : "."
            texto = r.prefix(1).uppercased() + r.dropFirst() + fin
        } else {
            let pauta = reps.map { r in p.series.map { "\($0)×\(r)" } ?? r }
            let reserva = frase(leyenda(p.rir))
            texto = "Seguí la pauta de esta semana\(pauta.map { " (\($0))" } ?? "")\(reserva.isEmpty ? "" : ",\(reserva)")."
        }
        return NotaProgresion(texto: texto, cambia: false, calibracion: calibracion)
    }
}
