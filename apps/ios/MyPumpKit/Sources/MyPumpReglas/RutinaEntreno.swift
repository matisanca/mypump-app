import Foundation
import MyPumpModelos

// Entreno, lo que es de la rutina y de la semana: normalizarRutina (ENT-04), los rótulos de día y de bloque (ENT-01,
// ENT-05), el banner de progresión y la calibración (ENT-07, ENT-08), y los textos de avanzar semana, bloque nuevo y día
// completado (ENT-14, ENT-15, ENT-17). Port de cliente.html; lo verifican los vectores de
// scripts/nativa/vectores-entreno.mjs, que corren esas mismas funciones de la web.

/// Una pregunta de la web (`MyPump.ui.showConfirmModal`), con sus textos exactos. La app la muestra y contesta.
public struct Pregunta: Equatable, Sendable {
    public let titulo: String
    public let cuerpo: String
    public let confirmar: String
    public let cancelar: String

    public init(titulo: String, cuerpo: String, confirmar: String, cancelar: String) {
        self.titulo = titulo; self.cuerpo = cuerpo; self.confirmar = confirmar; self.cancelar = cancelar
    }
}

/// Lo que devuelve `normalizarRutina`: si se puede entrenar con el plan, el plan con los huecos rellenados y lo que le
/// faltaba (para el aviso "a tu plan le falta información", GEN-05).
public struct RutinaNormalizada: Sendable, Equatable {
    public let usable: Bool
    public let estructura: EstructuraRutina
    public let problemas: [String]
}

public enum NormalizacionRutina {
    /// `DESCANSO_POR_DEFECTO`: lo que usa el generador para aislados.
    public static let descansoPorDefecto = 90

    /// `normalizarRutina` (cliente.html:1799): día sin id → `d<n>`, sin nombre → "Día n"; descanso ausente o ≤ 0 → 90;
    /// series ≤ 0 → 1; `semanas_total` ausente o ≤ 0 → 12. Sin días, o sin un solo ejercicio, no es usable.
    ///
    /// Lo que la web corrige del JSON crudo y acá ya corrigió el decodificador (Rutina.swift): un bloque, día o
    /// ejercicio que no es un objeto se descarta (la web lo vuelve un objeto vacío) y un día sin la clave `bloques` es
    /// un día sin bloques (la web suma además "sin bloques."). Están en `excepciones` de los vectores.
    public static func normalizar(_ e: EstructuraRutina?) -> RutinaNormalizada {
        var est = e ?? EstructuraRutina()
        guard !est.dias.isEmpty else {
            return RutinaNormalizada(usable: false, estructura: est, problemas: ["El plan no tiene días cargados."])
        }
        var problemas: [String] = []
        for i in est.dias.indices {
            var d = est.dias[i]
            if JS.verdadero(d.id) == nil { d.id = "d\(i + 1)" }
            if JS.verdadero(d.nombre) == nil { d.nombre = "Día \(i + 1)" }
            for b in d.bloques.indices {
                for x in d.bloques[b].ejercicios.indices {
                    var ej = d.bloques[b].ejercicios[x]
                    // Sin esto el chip muestra NaN:NaN y el descanso arranca y no para.
                    if !((ej.descansoSegundos ?? 0) > 0) { ej.descansoSegundos = descansoPorDefecto }
                    if !((ej.series ?? 0) > 0) { ej.series = 1 }
                    d.bloques[b].ejercicios[x] = ej
                }
            }
            if !d.bloques.contains(where: { !$0.ejercicios.isEmpty }) { problemas.append("\(d.nombre ?? ""): sin ejercicios.") }
            est.dias[i] = d
        }
        // semanas_total ausente: el front decía 1 y el server 12 ("SEM 4/1" y sin botón de avanzar).
        if !((est.semanasTotal ?? 0) > 0) {
            est.semanasTotal = 12
            problemas.append("El plan no dice cuántas semanas dura; se asume 12.")
        }
        guard est.dias.contains(where: { $0.bloques.contains { !$0.ejercicios.isEmpty } }) else {
            return RutinaNormalizada(usable: false, estructura: est, problemas: ["Ningún día del plan tiene ejercicios."])
        }
        return RutinaNormalizada(usable: true, estructura: est, problemas: problemas)
    }
}

public enum TextosEntreno {
    /// `getDayShortName` (ENT-01): la primera palabra del nombre (corta en blanco, guion, raya o barra) con la primera
    /// letra en mayúscula y el resto en minúscula. "TIRÓN A — ANCHO" → "Tirón".
    public static func nombreCortoDia(_ nombre: String?) -> String {
        guard let nombre = JS.verdadero(nombre) else { return "" }
        let primera = JS.trim(separadorDia.antesDeLaPrimera(nombre))
        let u = Array(primera.utf16)
        guard let c0 = u.first else { return "" }
        // `charAt(0)` es una unidad UTF-16: con un emoji es media letra, que no cambia de caja; la otra mitad tampoco.
        if UTF16.isLeadSurrogate(c0) {
            let escalares = primera.unicodeScalars
            return String(escalares.first!) + JS.minusculas(String(escalares.dropFirst()))
        }
        return JS.mayusculas(String(decoding: [c0], as: UTF16.self)) + JS.minusculas(String(decoding: u.dropFirst(), as: UTF16.self))
    }

    static let separadorDia = RegexWeb(#"[\s–—\-\/]"#)

    /// `getDayNum`: `dia.n`, o la posición del día (por id) en la rutina, o 1.
    public static func numeroDia(_ dia: Dia, en dias: [Dia]) -> Int {
        if let n = dia.n { return n }
        return dias.firstIndex { JS.iguales($0.id, dia.id) }.map { $0 + 1 } ?? 1
    }

    /// `getNombreBloque` (ENT-05): el subtítulo en mayúsculas, o lo que sigue a "BLOQUE n —" del título.
    public static func nombreBloque(_ b: Bloque) -> String {
        if let s = JS.verdadero(b.subtitulo) { return JS.mayusculas(s) }
        guard let raw = JS.verdadero(b.titulo) else { return "" }
        if let resto = bloqueNumerado.grupo(raw, 1) { return JS.mayusculas(JS.trim(resto)) }
        return JS.mayusculas(raw)
    }

    static let bloqueNumerado = RegexWeb(#"^bloque\s+\d+\s*[—–-]\s*(.+)$"#, i: true)

    /// `getSuggestedDay` (ENT-02): el último día que se vio en este teléfono, o el primero. No usa el calendario.
    public static func diaSugerido(_ dias: [Dia], ultimo: String?) -> Dia? {
        if let ultimo = JS.verdadero(ultimo), let d = dias.first(where: { JS.iguales($0.id, ultimo) }) { return d }
        return dias.first
    }

    // Textos fijos de la pantalla (los compara el test con los de la web).
    public static let diaVacio = "Este día no tiene ejercicios cargados.\nSi es un día de descanso, ¡a descansar! Si no, avisale a Mati."
    public static let demo = "⚠ Modo demo — Mati todavía no publicó tu plan. Los datos que ves son de ejemplo."
    public static let empezar = "Empezar entrenamiento"
    public static let empezarDetalle = "arranca el cronómetro de la sesión — o empezá directo: corre solo con tu primera serie"
    public static let sinCerrar = "quedó abierta de antes — no te preocupes, no perdiste nada"
    public static let porPrimeraSerie = "⏱ arrancó con tu primera serie"
    public static let sinComentarios = "Todavía no hay comentarios. Dejale una nota a Mati o contale cómo te fue."
    public static let comentarioFallo = "No se pudo enviar el comentario. Probá de nuevo."
    public static let cerrarSinSesion = "No se pudo guardar la sesión. Revisá tu conexión e intentá de nuevo."
    public static let cerrarFallo = "No se pudo cerrar la sesión. Revisá tu conexión e intentá de nuevo."
    public static let sinVariantes = "No hay otra variante equivalente del mismo gesto para este ejercicio."
}

/// El cartel de arriba del día (ENT-07/08).
public struct BannerSemana: Equatable, Sendable {
    /// Ejercicios (sin el calentamiento) cuya nota de progresión dice que cambian.
    public let cambian: Int
    /// Semana 1 sin offset (el primer macrociclo): "🎯 Semana de calibración".
    public let calibracion: Bool

    /// El texto que muestra, o nil si no hay cartel.
    public var texto: String? {
        if cambian > 0 {
            return "📈 Esta semana \(cambian) \(cambian == 1 ? "ejercicio cambia" : "ejercicios cambian") carga o volumen. Mirá el detalle al abrir cada uno."
        }
        if calibracion {
            return "🎯 Semana de calibración: llegá cerca del fallo muscular y encontrá tu peso real. Las reps son una guía (±2-3) — no te guardes reps."
        }
        return nil
    }
}

public enum SemanaEntreno {
    /// El banner de `renderTrain`: cuántos ejercicios cambian carga o volumen, o la calibración de la semana 1.
    public static func banner(_ dia: Dia, semana: Int, offset: Int) -> BannerSemana {
        let n = dia.bloques.flatMap(\.ejercicios).filter { $0.tipo != "calentamiento" && Progresiones.nota($0, semanaActual: semana)?.cambia == true }.count
        // Calibración solo en la semana 1 del PRIMER macrociclo (fase 2+ continúa cargas).
        return BannerSemana(cambian: n, calibracion: (semana == 0 ? 1 : semana) <= 1 && offset == 0)
    }

    /// ENT-14: el botón "Pasar a Semana N →" se ve si no es la demo y no es la última semana.
    public static func puedeAvanzar(semana: Int, total: Int, demo: Bool) -> Bool { !demo && semana < total }

    /// ENT-15: en la última semana, con un bloque en cola, "🎉 Empezar bloque nuevo →".
    public static func puedeEmpezarBloque(semana: Int, total: Int, tieneSiguiente: Bool, demo: Bool) -> Bool {
        !demo && semana >= total && tieneSiguiente
    }

    /// El rótulo del botón (`semana_offset` solo cambia rótulos, ENT-09).
    public static func botonAvanzar(semana: Int, offset: Int) -> String { "Pasar a Semana \(semana + offset + 1) →" }
    public static let botonBloqueNuevo = "🎉 Empezar bloque nuevo →"
    public static let detalleBloqueNuevo = "Terminaste tu plan. Tu próximo bloque ya está listo."

    /// `confirmAvanzarSemana`: nil en la última semana (no hay a dónde avanzar).
    public static func preguntaAvanzar(semana: Int, total: Int, offset: Int, diaCompleto: Bool) -> Pregunta? {
        guard semana < total else { return nil }
        let siguiente = semana + offset + 1
        return Pregunta(
            titulo: "Pasar a Semana \(siguiente)",
            cuerpo: diaCompleto
                ? "¿Confirmás que querés avanzar a la SEMANA \(siguiente)?"
                : "Todavía tenés ejercicios sin completar en la SEMANA \(semana + offset). Si avanzás, la semana nueva empieza con progresión actualizada. ¿Continuar?",
            confirmar: "Pasar a SEM \(siguiente) →", cancelar: "Cancelar")
    }

    /// `doAvanzarSemana` cuando no salió: sin red se ofrece recargar (el servidor puede haber avanzado igual).
    public static func errorAvanzar(sinRed: Bool) -> Pregunta {
        Pregunta(titulo: sinRed ? "Sin conexión" : "No se pudo pasar de semana",
                 cuerpo: sinRed ? "No pudimos avisarle al servidor. Cuando tengas señal, recargá y fijate en qué semana quedaste."
                     : "Probá de nuevo en un rato. Si sigue así, escribile a Mati.",
                 confirmar: "Recargar", cancelar: "Cerrar")
    }

    /// `confirmEmpezarBloqueNuevo`
    public static let preguntaBloqueNuevo = Pregunta(
        titulo: "¡Nuevo bloque!",
        cuerpo: "Terminaste tu plan 💪. Tu coach ya te dejó preparado el siguiente bloque. ¿Lo empezamos? Vas a arrancar en la primera semana del bloque nuevo — tus cargas anteriores quedan guardadas.",
        confirmar: "🎉 Empezar bloque nuevo →", cancelar: "Ahora no")

    /// `doEmpezarBloqueNuevo` cuando no salió.
    public static func errorBloqueNuevo(sinRed: Bool) -> Pregunta {
        Pregunta(titulo: sinRed ? "Sin conexión" : "Ups",
                 cuerpo: sinRed ? "No llegó la respuesta del servidor. Recargá para ver si el bloque nuevo ya quedó activo."
                     : "No pudimos activar el bloque nuevo. Probá de nuevo en un rato o escribile a tu coach.",
                 confirmar: sinRed ? "Recargar" : "Ok", cancelar: sinRed ? "Cerrar" : "")
    }

    /// `showDayCompletedModal` (ENT-17): con un día siguiente, ofrece ir; si es el último, solo felicita.
    public static func preguntaDiaCompletado(dias: [Dia], actual: String?) -> (pregunta: Pregunta, siguiente: Dia?) {
        let i = dias.firstIndex { JS.iguales($0.id, actual) }
        guard let i, i + 1 < dias.count else {
            return (Pregunta(titulo: "🎉 ¡Día completado!",
                             cuerpo: "Buen trabajo. Cuando hayas terminado todos los días de la semana, usá el botón \"Pasar a Semana N+1\" abajo para avanzar.",
                             confirmar: "Listo", cancelar: "Cerrar"), nil)
        }
        let siguiente = dias[i + 1]
        let nombre = JS.verdadero(siguiente.nombre) ?? "Día \(i + 2)"
        return (Pregunta(titulo: "🎉 ¡Día completado!", cuerpo: "Buen trabajo. ¿Querés ir al siguiente día (\(nombre))?",
                         confirmar: "Ir a \(nombre) →", cancelar: "Ahora no"), siguiente)
    }
}
