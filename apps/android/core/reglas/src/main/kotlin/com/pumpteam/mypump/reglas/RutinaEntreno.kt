package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Bloque
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.EstructuraRutina

// Entreno, lo que es de la rutina y de la semana: normalizarRutina (ENT-04), los rótulos de día y de bloque (ENT-01,
// ENT-05), el banner de progresión y la calibración (ENT-07, ENT-08), y los textos de avanzar semana, bloque nuevo y día
// completado (ENT-14, ENT-15, ENT-17). Port de cliente.html, como RutinaEntreno.swift; lo verifican los vectores de
// scripts/nativa/vectores-entreno.mjs, que corren esas mismas funciones de la web.

/** Una pregunta de la web (`MyPump.ui.showConfirmModal`), con sus textos exactos. La app la muestra y contesta. */
data class Pregunta(val titulo: String, val cuerpo: String, val confirmar: String, val cancelar: String)

/**
 * Lo que devuelve `normalizarRutina`: si se puede entrenar con el plan, el plan con los huecos rellenados y lo que le
 * faltaba (para el aviso "a tu plan le falta información", GEN-05).
 */
data class RutinaNormalizada(val usable: Boolean, val estructura: EstructuraRutina, val problemas: List<String>)

object NormalizacionRutina {
    /** `DESCANSO_POR_DEFECTO`: lo que usa el generador para aislados. */
    const val DESCANSO_POR_DEFECTO = 90

    /**
     * `normalizarRutina` (cliente.html:1799): día sin id → `d<n>`, sin nombre → "Día n"; descanso ausente o ≤ 0 → 90;
     * series ≤ 0 → 1; `semanas_total` ausente o ≤ 0 → 12. Sin días, o sin un solo ejercicio, no es usable.
     *
     * Lo que la web corrige del JSON crudo y acá ya corrigió el decodificador (Rutina.kt): un bloque, día o ejercicio que
     * no es un objeto se descarta (la web lo vuelve un objeto vacío) y un día sin la clave `bloques` es un día sin
     * bloques. Están en `excepciones` de los vectores.
     */
    fun normalizar(e: EstructuraRutina?): RutinaNormalizada {
        var est = e ?: EstructuraRutina()
        if (est.dias.isEmpty()) return RutinaNormalizada(false, est, listOf("El plan no tiene días cargados."))
        val problemas = mutableListOf<String>()
        val dias = est.dias.mapIndexed { i, original ->
            var d = original
            if (Js.verdadero(d.id) == null) d = d.copy(id = "d${i + 1}")
            if (Js.verdadero(d.nombre) == null) d = d.copy(nombre = "Día ${i + 1}")
            d = d.copy(
                bloques = d.bloques.map { b ->
                    b.copy(
                        ejercicios = b.ejercicios.map { ej ->
                            var x = ej
                            // Sin esto el chip muestra NaN:NaN y el descanso arranca y no para.
                            if (!((x.descansoSegundos ?: 0) > 0)) x = x.copy(descansoSegundos = DESCANSO_POR_DEFECTO)
                            if (!((x.series ?: 0) > 0)) x = x.copy(series = 1)
                            x
                        },
                    )
                },
            )
            if (d.bloques.none { it.ejercicios.isNotEmpty() }) problemas += "${d.nombre ?: ""}: sin ejercicios."
            d
        }
        est = est.copy(dias = dias)
        // semanas_total ausente: el front decía 1 y el server 12 ("SEM 4/1" y sin botón de avanzar).
        if (!((est.semanasTotal ?: 0) > 0)) {
            est = est.copy(semanasTotal = 12)
            problemas += "El plan no dice cuántas semanas dura; se asume 12."
        }
        if (est.dias.none { d -> d.bloques.any { it.ejercicios.isNotEmpty() } }) {
            return RutinaNormalizada(false, est, listOf("Ningún día del plan tiene ejercicios."))
        }
        return RutinaNormalizada(true, est, problemas)
    }
}

object TextosEntreno {
    /**
     * `getDayShortName` (ENT-01): la primera palabra del nombre (corta en blanco, guion, raya o barra) con la primera
     * letra en mayúscula y el resto en minúscula. "TIRÓN A — ANCHO" → "Tirón". Como en JS, `charAt(0)` es una unidad
     * UTF-16: con un emoji es media letra, que no cambia de caja (Kotlin hace lo mismo con una mitad suelta).
     */
    fun nombreCortoDia(nombre: String?): String {
        val n = Js.verdadero(nombre) ?: return ""
        val primera = Js.trim(separadorDia.antesDeLaPrimera(n))
        if (primera.isEmpty()) return ""
        return Js.mayusculas(primera.substring(0, 1)) + Js.minusculas(primera.substring(1))
    }

    private val separadorDia = JsRegex("""[\s–—\-\/]""")

    /** `getDayNum`: `dia.n`, o la posición del día (por id) en la rutina, o 1. */
    fun numeroDia(dia: Dia, dias: List<Dia>): Int {
        dia.n?.let { return it }
        val i = dias.indexOfFirst { it.id == dia.id }
        return if (i >= 0) i + 1 else 1
    }

    /** `getNombreBloque` (ENT-05): el subtítulo en mayúsculas, o lo que sigue a "BLOQUE n —" del título. */
    fun nombreBloque(b: Bloque): String {
        Js.verdadero(b.subtitulo)?.let { return Js.mayusculas(it) }
        val raw = Js.verdadero(b.titulo) ?: return ""
        bloqueNumerado.grupo(raw, 1)?.let { return Js.mayusculas(Js.trim(it)) }
        return Js.mayusculas(raw)
    }

    private val bloqueNumerado = JsRegex("""^bloque\s+\d+\s*[—–-]\s*(.+)$""", "i")

    /** `getSuggestedDay` (ENT-02): el último día que se vio en este teléfono, o el primero. No usa el calendario. */
    fun diaSugerido(dias: List<Dia>, ultimo: String?): Dia? {
        Js.verdadero(ultimo)?.let { u -> dias.firstOrNull { it.id == u }?.let { return it } }
        return dias.firstOrNull()
    }

    // Textos fijos de la pantalla (los compara el test con los de la web).
    const val DIA_VACIO = "Este día no tiene ejercicios cargados.\nSi es un día de descanso, ¡a descansar! Si no, avisale a Mati."
    const val DEMO = "⚠ Modo demo — Mati todavía no publicó tu plan. Los datos que ves son de ejemplo."
    const val EMPEZAR = "Empezar entrenamiento"
    const val EMPEZAR_DETALLE = "arranca el cronómetro de la sesión — o empezá directo: corre solo con tu primera serie"
    const val SIN_CERRAR = "quedó abierta de antes — no te preocupes, no perdiste nada"
    const val POR_PRIMERA_SERIE = "⏱ arrancó con tu primera serie"
    const val SIN_COMENTARIOS = "Todavía no hay comentarios. Dejale una nota a Mati o contale cómo te fue."
    const val COMENTARIO_FALLO = "No se pudo enviar el comentario. Probá de nuevo."
    const val CERRAR_SIN_SESION = "No se pudo guardar la sesión. Revisá tu conexión e intentá de nuevo."
    const val CERRAR_FALLO = "No se pudo cerrar la sesión. Revisá tu conexión e intentá de nuevo."
    const val SIN_VARIANTES = "No hay otra variante equivalente del mismo gesto para este ejercicio."
}

/** El cartel de arriba del día (ENT-07/08). */
data class BannerSemana(
    /** Ejercicios (sin el calentamiento) cuya nota de progresión dice que cambian. */
    val cambian: Int,
    /** Semana 1 sin offset (el primer macrociclo): "🎯 Semana de calibración". */
    val calibracion: Boolean,
) {
    /** El texto que muestra, o null si no hay cartel. */
    val texto: String?
        get() {
            if (cambian > 0) {
                return "📈 Esta semana $cambian ${if (cambian == 1) "ejercicio cambia" else "ejercicios cambian"} carga o volumen. Mirá el detalle al abrir cada uno."
            }
            if (calibracion) {
                return "🎯 Semana de calibración: llegá cerca del fallo muscular y encontrá tu peso real. Las reps son una guía (±2-3) — no te guardes reps."
            }
            return null
        }
}

object SemanaEntreno {
    /** El banner de `renderTrain`: cuántos ejercicios cambian carga o volumen, o la calibración de la semana 1. */
    fun banner(dia: Dia, semana: Int, offset: Int): BannerSemana {
        val n = dia.bloques.flatMap { it.ejercicios }
            .count { it.tipo != "calentamiento" && Progresiones.nota(it, semanaActual = semana)?.cambia == true }
        // Calibración solo en la semana 1 del PRIMER macrociclo (fase 2+ continúa cargas).
        return BannerSemana(n, (if (semana == 0) 1 else semana) <= 1 && offset == 0)
    }

    /** ENT-14: el botón "Pasar a Semana N →" se ve si no es la demo y no es la última semana. */
    fun puedeAvanzar(semana: Int, total: Int, demo: Boolean): Boolean = !demo && semana < total

    /** ENT-15: en la última semana, con un bloque en cola, "🎉 Empezar bloque nuevo →". */
    fun puedeEmpezarBloque(semana: Int, total: Int, tieneSiguiente: Boolean, demo: Boolean): Boolean =
        !demo && semana >= total && tieneSiguiente

    /** El rótulo del botón (`semana_offset` solo cambia rótulos, ENT-09). */
    fun botonAvanzar(semana: Int, offset: Int): String = "Pasar a Semana ${semana + offset + 1} →"
    const val BOTON_BLOQUE_NUEVO = "🎉 Empezar bloque nuevo →"
    const val DETALLE_BLOQUE_NUEVO = "Terminaste tu plan. Tu próximo bloque ya está listo."

    /** `confirmAvanzarSemana`: null en la última semana (no hay a dónde avanzar). */
    fun preguntaAvanzar(semana: Int, total: Int, offset: Int, diaCompleto: Boolean): Pregunta? {
        if (semana >= total) return null
        val siguiente = semana + offset + 1
        return Pregunta(
            titulo = "Pasar a Semana $siguiente",
            cuerpo = if (diaCompleto) {
                "¿Confirmás que querés avanzar a la SEMANA $siguiente?"
            } else {
                "Todavía tenés ejercicios sin completar en la SEMANA ${semana + offset}. Si avanzás, la semana nueva empieza con progresión actualizada. ¿Continuar?"
            },
            confirmar = "Pasar a SEM $siguiente →", cancelar = "Cancelar",
        )
    }

    /** `doAvanzarSemana` cuando no salió: sin red se ofrece recargar (el servidor puede haber avanzado igual). */
    fun errorAvanzar(sinRed: Boolean): Pregunta = Pregunta(
        titulo = if (sinRed) "Sin conexión" else "No se pudo pasar de semana",
        cuerpo = if (sinRed) {
            "No pudimos avisarle al servidor. Cuando tengas señal, recargá y fijate en qué semana quedaste."
        } else {
            "Probá de nuevo en un rato. Si sigue así, escribile a Mati."
        },
        confirmar = "Recargar", cancelar = "Cerrar",
    )

    /** `confirmEmpezarBloqueNuevo` */
    val preguntaBloqueNuevo = Pregunta(
        titulo = "¡Nuevo bloque!",
        cuerpo = "Terminaste tu plan 💪. Tu coach ya te dejó preparado el siguiente bloque. ¿Lo empezamos? Vas a arrancar en la primera semana del bloque nuevo — tus cargas anteriores quedan guardadas.",
        confirmar = "🎉 Empezar bloque nuevo →", cancelar = "Ahora no",
    )

    /** `doEmpezarBloqueNuevo` cuando no salió. */
    fun errorBloqueNuevo(sinRed: Boolean): Pregunta = Pregunta(
        titulo = if (sinRed) "Sin conexión" else "Ups",
        cuerpo = if (sinRed) {
            "No llegó la respuesta del servidor. Recargá para ver si el bloque nuevo ya quedó activo."
        } else {
            "No pudimos activar el bloque nuevo. Probá de nuevo en un rato o escribile a tu coach."
        },
        confirmar = if (sinRed) "Recargar" else "Ok", cancelar = if (sinRed) "Cerrar" else "",
    )

    /** `showDayCompletedModal` (ENT-17): con un día siguiente, ofrece ir; si es el último, solo felicita. */
    fun preguntaDiaCompletado(dias: List<Dia>, actual: String?): Pair<Pregunta, Dia?> {
        val i = dias.indexOfFirst { it.id == actual }
        if (i < 0 || i + 1 >= dias.size) {
            return Pregunta(
                titulo = "🎉 ¡Día completado!",
                cuerpo = "Buen trabajo. Cuando hayas terminado todos los días de la semana, usá el botón \"Pasar a Semana N+1\" abajo para avanzar.",
                confirmar = "Listo", cancelar = "Cerrar",
            ) to null
        }
        val siguiente = dias[i + 1]
        val nombre = Js.verdadero(siguiente.nombre) ?: "Día ${i + 2}"
        return Pregunta(
            titulo = "🎉 ¡Día completado!", cuerpo = "Buen trabajo. ¿Querés ir al siguiente día ($nombre)?",
            confirmar = "Ir a $nombre →", cancelar = "Ahora no",
        ) to siguiente
    }
}
