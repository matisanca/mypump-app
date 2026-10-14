package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Comentario
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Imagenes
import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId

// Entreno, lo que es de la sesión: el cronómetro con el tope de 6 h (SES-03), el descanso como fecha de fin persistida
// (SES-04), los comentarios por ejercicio (SES-08) y la poda de sustituciones (SER-12). Port de cliente.html, como
// SesionEntreno.swift; lo verifican los vectores de scripts/nativa/vectores-entreno.mjs. Los tiempos van en
// milisegundos desde 1970, como `Date.now()`.

object TiempoEntreno {
    /** `SESION_MAX_H`: más que esto no es un entrenamiento largo, es un día que quedó sin cerrar. */
    const val SESION_MAX_H = 6.0

    /** `fmtTime(s)`: "m:ss" (sin horas; 3600 s son "60:00"). */
    fun fmtTiempo(s: Double): String {
        val t = maxOf(0.0, s)
        val seg = Js.texto(t % 60)
        return "${Js.texto(Math.floor(t / 60))}:${if (seg.length < 2) "0$seg" else seg}"
    }

    /** `fmtCrono(ms)`: "m:ss" o "h:mm:ss". */
    fun fmtCrono(ms: Double): String {
        val s = maxOf(0.0, Math.floor(ms / 1000))
        val h = Math.floor(s / 3600)
        val m = Math.floor((s % 3600) / 60)
        val ss = s % 60
        fun p(n: Double): String = Js.texto(n).let { if (it.length < 2) "0$it" else it }
        return if (h > 0) "${Js.texto(h)}:${p(m)}:${p(ss)}" else "${Js.texto(m)}:${p(ss)}"
    }

    /**
     * `minutosSesion` (SES-03): los minutos de la sesión, o null si el número no es creíble (más de 6 h, o negativo). Lo
     * que se GUARDA y lo que se MUESTRA salen de acá.
     */
    fun minutosSesion(inicio: Double?, ahora: Double): Int? {
        if (inicio == null || inicio == 0.0) return null
        val seg = jsRound((ahora - inicio) / 1000)
        if (!(seg >= 0 && seg <= SESION_MAX_H * 3600)) return null
        return jsRound(seg / 60).toInt()
    }

    /** El cronómetro de arriba del día (`renderTrain`). */
    sealed interface Cronometro {
        /** "▶ Empezar entrenamiento" */
        data object Empezar : Cronometro

        /** "EN CURSO 12:34" (con "⏱ arrancó con tu primera serie" si no se tocó Empezar). */
        data class EnCurso(val texto: String, val porBoton: Boolean) : Cronometro

        /** Más de 6 h: "SIN CERRAR · Empezar de nuevo" (la duración que se guarda va null). */
        data object SinCerrar : Cronometro
    }

    /** null cuando el día está cerrado o todo hecho (ahí está la card de cierre). */
    fun cronometro(inicio: Double?, ahora: Double, porBoton: Boolean, diaFinalizado: Boolean, todoHecho: Boolean): Cronometro? {
        if (diaFinalizado || todoHecho) return null
        if (inicio == null || inicio == 0.0) return Cronometro.Empezar
        if (ahora - inicio > SESION_MAX_H * 3_600_000) return Cronometro.SinCerrar
        return Cronometro.EnCurso(fmtCrono(ahora - inicio), porBoton)
    }
}

/**
 * El descanso entre series (SES-04): anclado al reloj (fin y cierre), así una app en segundo plano no se atrasa. Se
 * guarda en disco igual que la web guardaba `mypump_rest_<TOKEN>`.
 */
data class Descanso(
    /** `endsAt` (ms) */
    val fin: Double,
    /** `target` (s): lo que se pidió, más lo que se sumó con +15. */
    val objetivo: Double,
    /** `autoCloseAt` (ms): 2 s después del fin se cierra la barra. */
    val cierre: Double,
    /** `doneFired`: ya sonó. */
    val terminado: Boolean,
) {
    /** Lo que va a disco: `{endsAt, target, autoCloseAt}`. */
    data class Guardado(val endsAt: Double, val target: Double, val autoCloseAt: Double?) {
        fun aValor(): ValorJson = ValorJson.objeto(
            "endsAt" to ValorJson.Numero(endsAt), "target" to ValorJson.Numero(target),
            "autoCloseAt" to (autoCloseAt?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo),
        )

        companion object {
            fun desde(v: ValorJson?): Guardado? {
                val endsAt = v?.get("endsAt")?.comoNumero ?: return null
                val target = v["target"]?.comoNumero ?: return null
                return Guardado(endsAt, target, v["autoCloseAt"]?.comoNumero)
            }
        }
    }

    /** Lo que devuelve un tick: el descanso, si terminó en este tick (suena) y si ya hay que cerrar la barra. */
    data class Tick(val descanso: Descanso, val termino: Boolean, val cerrar: Boolean)

    /**
     * −15 / +15: corre el fin y el cierre; solo lo que se suma agranda el objetivo. Si el fin vuelve a quedar adelante,
     * puede sonar de nuevo.
     */
    fun ajustado(segundos: Double, ahora: Double): Descanso {
        val nuevoFin = fin + segundos * 1000
        return Descanso(
            fin = nuevoFin,
            objetivo = if (segundos > 0) objetivo + segundos else objetivo,
            cierre = cierre + segundos * 1000,
            terminado = if (nuevoFin > ahora) false else terminado,
        )
    }

    /** `restTick`: `termino` la primera vez que se cruza el fin (sonido y vibración); `cerrar` al pasar el cierre. */
    fun tick(ahora: Double): Tick {
        val termino = ahora >= fin && !terminado
        return Tick(if (termino) copy(terminado = true) else this, termino, ahora >= cierre)
    }

    val guardado: Guardado get() = Guardado(fin, objetivo, cierre)

    /** Segundos que faltan, redondeados hacia arriba. */
    fun restante(ahora: Double): Double = maxOf(0.0, Math.ceil((fin - ahora) / 1000))

    /** "1:29" */
    fun texto(ahora: Double): String = TiempoEntreno.fmtTiempo(restante(ahora))

    /** "/ 1:30 objetivo" */
    val textoObjetivo: String get() = "/ ${TiempoEntreno.fmtTiempo(objetivo)} objetivo"

    /** 0-100 de la barra. */
    fun porcentaje(ahora: Double): Double = maxOf(0.0, minOf(100.0, ((objetivo - restante(ahora)) / objetivo) * 100))

    companion object {
        /** `startRest(seconds)`. El 90 por defecto ya lo puso `normalizarRutina` en `descanso_segundos`. */
        fun iniciar(segundos: Double, ahora: Double): Descanso =
            Descanso(fin = ahora + segundos * 1000, objetivo = segundos, cierre = ahora + (segundos + 2) * 1000, terminado = false)

        /** `restoreRest`: lo guardado, si todavía no se cerró. Si ya pasó el fin, no vuelve a sonar. */
        fun restaurar(g: Guardado?, ahora: Double): Descanso? {
            val cierre = g?.autoCloseAt ?: return null
            if (cierre == 0.0 || !(ahora < cierre)) return null
            return Descanso(fin = g.endsAt, objetivo = g.target, cierre = cierre, terminado = ahora >= g.endsAt)
        }
    }
}

/**
 * La barra del descanso: lo que hacen `startRest`, `restTick`, `stopRest`, `restoreRest` y los botones −15 / +15 / Saltar
 * de la web, con lo que queda en disco (`guardado`). Sin sonido ni vibración: eso es de la app. Se muta en el lugar;
 * [copia] da otra igual (el modelo publica una copia nueva en cada cambio).
 */
class BarraDescanso(guardado: Descanso.Guardado? = null) {
    var descanso: Descanso? = null
        private set

    /** Lo que está en disco (`mypump_rest_<TOKEN>`); null es "nada guardado". */
    var guardado: Descanso.Guardado? = guardado
        private set
    var visible = false
        private set

    /** Terminó (la barra verde). */
    var listo = false
        private set

    /** "1:29" */
    var texto = ""
        private set

    /** "/ 1:30 objetivo" */
    var textoObjetivo = ""
        private set

    /** 0-100; null hasta que se pinta por primera vez. */
    var porcentaje: Double? = null
        private set

    fun copia(): BarraDescanso = BarraDescanso(guardado).also {
        it.descanso = descanso
        it.visible = visible
        it.listo = listo
        it.texto = texto
        it.textoObjetivo = textoObjetivo
        it.porcentaje = porcentaje
    }

    /** `startRest` */
    fun iniciar(segundos: Double, ahora: Double) {
        detener()
        val d = Descanso.iniciar(segundos, ahora)
        descanso = d
        visible = true
        listo = false
        pintar(ahora)
        guardado = d.guardado
    }

    /** `restTick`: devuelve true la vez que termina (la app suena y vibra). A los 2 s del fin se cierra. */
    fun tick(ahora: Double): Boolean {
        val d = descanso ?: return false
        val t = d.tick(ahora)
        descanso = t.descanso
        if (t.termino) listo = true
        if (t.cerrar) {
            detener()
            return t.termino
        }
        pintar(ahora)
        return t.termino
    }

    /** Los botones: "-15", "15" o "skip". */
    fun ajustar(v: String, ahora: Double) {
        val d = descanso ?: return
        if (v == "skip") {
            detener()
            return
        }
        val n = d.ajustado(Js.parseInt(v, base10 = false) ?: Double.NaN, ahora)
        descanso = n
        if (n.fin > ahora) listo = false
        pintar(ahora)
        guardado = n.guardado
    }

    /** `stopRest`: se va la barra y lo guardado. */
    fun detener() {
        descanso = null
        visible = false
        listo = false
        guardado = null
    }

    /**
     * `restoreRest`: lo guardado vuelve si todavía no se cerró. Como en la web, restaurar borra lo guardado (el
     * `stopRest` de adentro lo limpia y no se vuelve a escribir).
     */
    fun restaurar(ahora: Double) {
        val g = guardado ?: return
        val cierre = g.autoCloseAt ?: return
        if (cierre == 0.0) return
        if (ahora >= cierre) {
            guardado = null
            return
        }
        detener()
        val d = Descanso.restaurar(g, ahora) ?: return
        descanso = d
        visible = true
        listo = d.terminado
        pintar(ahora)
    }

    /** `updateRestUI` */
    private fun pintar(ahora: Double) {
        val d = descanso ?: return
        texto = d.texto(ahora)
        textoObjetivo = d.textoObjetivo
        porcentaje = d.porcentaje(ahora)
    }
}

/** Los comentarios coach ↔ cliente indexados por `ambito|referencia_id` (los badges y la sección de cada card). */
class IndiceComentarios private constructor(
    val porReferencia: Map<String, List<Comentario>>,
    /** Sin leer por `ambito|referencia`. */
    val sinLeerPorClave: Map<String, Int>,
) {
    constructor(filas: List<Comentario> = emptyList()) : this(
        filas.groupBy { clave(it.ambito, it.referenciaId) },
        LinkedHashMap<String, Int>().apply {
            for (c in filas) {
                if (c.autor == "coach" && c.leidoPorCliente != true) merge(clave(c.ambito, c.referenciaId), 1, Int::plus)
            }
        },
    )

    fun comentarios(ejercicio: String): List<Comentario> = porReferencia[clave("ejercicio", ejercicio)] ?: emptyList()

    fun sinLeer(ejercicio: String): Int = sinLeerPorClave[clave("ejercicio", ejercicio)] ?: 0

    /** `totalUnreadComentarios`: el badge de Entreno, SIN el chat (`general|`), que tiene el suyo. */
    val totalEntreno: Int get() = sinLeerPorClave.filterKeys { !it.startsWith("general|") }.values.sum()

    /** `getUnreadDia`: el 💬 del selector de días. */
    fun sinLeerDia(dia: Dia): Int = dia.bloques.flatMap { it.ejercicios }.sumOf { sinLeer(it.id) }

    /** `marcarLeidosEjercicio`, optimista: el badge se va ya; la base se avisa aparte. */
    fun marcarLeidos(ejercicio: String): IndiceComentarios {
        val k = clave("ejercicio", ejercicio)
        val refs = porReferencia[k]?.let { l -> porReferencia + (k to l.map { if (it.autor == "coach") it.copy(leidoPorCliente = true) else it }) }
            ?: porReferencia
        return IndiceComentarios(refs, sinLeerPorClave + (k to 0))
    }

    companion object {
        /** `_comKey`: `${ambito}|${refId || ''}` */
        fun clave(ambito: String, referencia: String?): String = "$ambito|${referencia ?: ""}"

        /** "9+" desde 10. */
        fun badge(n: Int): String? = if (n > 0) (if (n > 9) "9+" else n.toString()) else null

        /** `fmtComentarioFecha`: "12-oct · 06:05 p. m." */
        fun fecha(iso: String, zona: ZoneId): String {
            val d = FechaJs.leer(iso) ?: return "Invalid Date · Invalid Date"
            return "${FechaJs.diaMes(d, zona)} · ${FechaJs.horaMinutos(d, zona)}"
        }
    }
}

/**
 * Las sustituciones de ejercicio que eligió el cliente (`STATE.exerciseSwaps`), con el MISMO formato que la web
 * (`mypump_exercise_swaps_<RUTINA>`): `exId → {original:{slug,nombre,images}, current:{slug,nombre,equipment,images},
 * fijado, semana, diaId}`. Se guardan crudas (JSON) para devolverlas igual y para que la migración del almacenamiento
 * viejo las copie tal cual.
 */
object SustitucionesEntreno {
    /**
     * Al cargar: las guardadas antes del flag "fijado" se tratan como FIJADAS (se eligieron cuando el swap era
     * permanente). Solo si la clave falta: un `null` explícito es "no fijada", como en la web.
     */
    fun compat(m: Map<String, ValorJson>): Map<String, ValorJson> = m.mapValues { (_, v) ->
        if (v is ValorJson.Objeto && !v.campos.containsKey("fijado")) ValorJson.Objeto(v.campos + ("fijado" to ValorJson.Booleano(true))) else v
    }

    /**
     * `pruneExerciseSwaps` (SER-12): las NO fijadas valen solo por la sesión de su día: se borran si son de otra semana o
     * si su día ya se cerró. Al CERRAR el día se conservan las del día abierto (para reabrir y corregir).
     */
    fun podar(
        m: Map<String, ValorJson>,
        semanaActual: Int,
        diasCompletados: Set<String>,
        diaActual: String?,
        diaFinalizado: Boolean,
        conservarDiaActual: Boolean,
    ): Pair<Map<String, ValorJson>, List<String>> {
        val quedan = LinkedHashMap(m)
        val borradas = mutableListOf<String>()
        val conservar = if (conservarDiaActual) Js.verdadero(diaActual) else null
        for ((exId, s) in m) {
            val o = s as? ValorJson.Objeto ?: continue
            if (SemanticaJs.esVerdadero(o["fijado"] ?: ValorJson.Nulo)) continue
            val diaId = (o["diaId"] as? ValorJson.Texto)?.valor
            if (conservar != null && diaId == conservar) continue
            val semana = o["semana"] ?: ValorJson.Nulo
            val otraSemana = semana != ValorJson.Nulo && semana != ValorJson.Numero(semanaActual.toDouble())
            var diaCerrado = false
            if (diaId != null && diaId.isNotEmpty() && diaId in diasCompletados) diaCerrado = true
            if (diaId != null && diaId == diaActual && diaFinalizado) diaCerrado = true
            if (otraSemana || diaCerrado) {
                quedan.remove(exId)
                borradas += exId
            }
        }
        return quedan to borradas
    }

    /** Lo que guarda `confirmExSwap` al elegir un sustituto. */
    fun nueva(sub: SustitutoEjercicio, original: EjercicioEfectivo, fijado: Boolean, semana: Int, diaId: String): ValorJson {
        fun imagenes(i: Imagenes?): ValorJson {
            if (i == null) return ValorJson.Nulo
            val o = linkedMapOf<String, ValorJson>(
                "eccentric" to (i.eccentric?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                "concentric" to (i.concentric?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            )
            i.matchedSlug?.let { o["_matched_slug"] = ValorJson.Texto(it) }
            return ValorJson.Objeto(o)
        }
        return ValorJson.objeto(
            "original" to ValorJson.objeto(
                "slug" to (Js.verdadero(original.slugOriginal)?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                "nombre" to ValorJson.Texto(Js.verdadero(original.nombreOriginal) ?: original.ejercicio.nombre),
                "images" to imagenes(original.imagenesOriginales),
            ),
            "current" to ValorJson.objeto(
                "slug" to (sub.slug?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                "nombre" to ValorJson.Texto(sub.nombre),
                "equipment" to (sub.equipoCrudo?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                "images" to imagenes(sub.imagenes),
            ),
            "fijado" to ValorJson.Booleano(fijado),
            "semana" to ValorJson.Numero(semana.toDouble()),
            "diaId" to ValorJson.Texto(diaId),
        )
    }

    /** El `current` de lo guardado, como lo usa `getEffectiveEx`. */
    fun aplicada(v: ValorJson?): SustitucionAplicada? {
        val o = v as? ValorJson.Objeto ?: return null
        val c = o["current"] as? ValorJson.Objeto ?: return null
        val imagenes = (c["images"] as? ValorJson.Objeto)?.let { Imagenes.desde(it.aJson()) }
        return SustitucionAplicada(
            slug = c["slug"]?.comoTexto, nombre = c["nombre"]?.comoTexto ?: "", equipo = c["equipment"]?.comoTexto,
            imagenes = imagenes, fijado = SemanticaJs.esVerdadero(o["fijado"] ?: ValorJson.Nulo),
        )
    }

    /** La búsqueda del modal: `name.toLowerCase().includes(query.toLowerCase().trim())`. */
    fun filtrar(subs: List<SustitutoEjercicio>, consulta: String): List<SustitutoEjercicio> {
        if (consulta.isEmpty()) return subs
        val q = Js.trim(Js.minusculas(consulta))
        return subs.filter { Js.minusculas(it.nombre).contains(q) }
    }
}
