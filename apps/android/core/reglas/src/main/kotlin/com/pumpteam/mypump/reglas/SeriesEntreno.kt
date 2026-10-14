package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

// Entreno, lo que es de cada serie: variantes y "sin kg" (SER-07, ENT-13), los sugeridos de un toque y el kg heredado
// (SER-01, SER-03), la lectura de los campos (SER-04), el RIR (SER-02), los topes y las preguntas (SER-05), el récord y
// "Última vez" (SER-08) y lo que viaja en la cola (`writeSet`, `writeExerciseStatus`). Port de cliente.html, como
// SeriesEntreno.swift; lo verifican los vectores de scripts/nativa/vectores-entreno.mjs.

/** Una serie del día (`STATE.session[ex].sets[i]`). Los campos son texto, como en la web: lo que tipeó el cliente. */
data class SerieLocal(
    val reps: String = "",
    val kg: String = "",
    /** "" = no lo cargó; "0" = fue al fallo (RIR 0 ≠ null, SER-02). */
    val rir: String = "",
    val confirmada: Boolean = false,
    /** Con qué nombre se registró (el del sustituto, si sustituyó): reabrir el día no la renombra al original. */
    val nombreRegistrado: String? = null,
    /** La variante con la que se registró ESTA serie (la del ejercicio cambia; la de la serie no). */
    val varianteRegistrada: String? = null,
    /** El aviso de la fila dudosa ("Revisá las repeticiones: 1214"). Se borra al tipear. */
    val aviso: String? = null,
)

/** Un ejercicio del día en la sesión (`STATE.session[ex]`). */
data class EjercicioEnSesion(
    val series: List<SerieLocal>,
    /** `completed` */
    val completo: Boolean = false,
    /** `status`: pendiente, completo, completo_sin_datos o saltado. */
    val estado: String = "pendiente",
    /** La variante elegida (agarre o nivel); null si el ejercicio no tiene. */
    val variante: String? = null,
)

/** Agarre o nivel de un ejercicio (`VARIANTES_EJ`): el peso y el historial se separan por variante. */
data class VariantesEjercicio(
    /** "Nivel" o "Agarre". */
    val etiqueta: String,
    /** La primera es la default (las filas viejas sin nota cuentan para ella). */
    val opciones: List<String>,
    /** Solo la rueda: de peso corporal, sin kg. */
    val sinPeso: Boolean,
)

object ReglasEjercicio {
    /** `VARIANTES_EJ`, copiado literal (el orden es la prioridad). */
    private val tabla: List<Pair<JsRegex, VariantesEjercicio>> = listOf(
        JsRegex("""rueda\s*abdom|ab\s*wheel|abdominal\s*wheel|rollout|roller\s*abdom""", "i") to
            VariantesEjercicio("Nivel", listOf("Rodillas flexionadas", "Rodillas extendidas"), sinPeso = true),
        JsRegex("""(tr(i|í)ceps|pushdown|jal(o|ó)n\s+de\s+tr(i|í)ceps).*(polea|cable)|polea.*tr(i|í)ceps""", "i") to
            VariantesEjercicio("Agarre", listOf("Barra", "Soga", "Maneral"), sinPeso = false),
        JsRegex("""jal(o|ó)n\s+(al|a la|de)\s+(pecho|nuca)|pulldown|dorsalera""", "i") to
            VariantesEjercicio("Agarre", listOf("Prono", "Supino", "Neutro"), sinPeso = false),
        JsRegex("""remo\s+(en\s+)?(polea|cable|gironda)|gironda""", "i") to
            VariantesEjercicio("Agarre", listOf("Neutro", "Ancho", "Supino"), sinPeso = false),
        JsRegex("""curl\s+.*(polea|cable)|polea.*curl""", "i") to
            VariantesEjercicio("Agarre", listOf("Barra", "Soga"), sinPeso = false),
    )

    /** `_SIN_PESO_RE` */
    private val sinPesoRE = JsRegex(
        """rueda\s*abdom|ab\s*wheel|rollout|plancha\b|abdominal(es)?\b|crunch|lagartija|flexi(o|ó)n(es)?\s+de\s+brazo|elevaci(o|ó)n(es)?\s+de\s+piernas|mountain\s*climber|hollow""",
        "i",
    )

    /** `_CON_CARGA_RE`: si el nombre menciona equipo o carga externa, lleva kg aunque el gesto sea de peso corporal. */
    private val conCargaRE = JsRegex(
        """m(a|á)quina|polea|cable|disco|lastre|mancuerna|barra\b|kettlebell|pesa\b|pesas\b|con\s+peso|con\s+carga|smith|multipower|banco\s+declinado\s+con""",
        "i",
    )
    private val sinTopeRE = JsRegex("""amrap|∞|max|máx""", "i")
    private val numerosRE = JsRegex("""\d+""")

    /** `getVariantesEntry` */
    fun variantes(nombre: String?): VariantesEjercicio? {
        val n = nombre ?: ""
        return tabla.firstOrNull { it.first.prueba(n) }?.second
    }

    /** `esSinPeso`: la carga externa gana; si no, la rueda o un gesto de peso corporal. El calentamiento va aparte. */
    fun esSinPeso(nombre: String?, tipo: String?): Boolean {
        if (tipo == "calentamiento") return false
        val n = nombre ?: ""
        if (conCargaRE.prueba(n)) return false
        return (variantes(n)?.sinPeso ?: false) || sinPesoRE.prueba(n)
    }

    /** `exNoKg` (ENT-13): sin columna de kg (calentamiento o peso corporal). */
    fun sinKg(nombre: String?, tipo: String?): Boolean = tipo == "calentamiento" || esSinPeso(nombre, tipo)

    fun sinKg(ex: Ejercicio): Boolean = sinKg(ex.nombre, ex.tipo)

    /**
     * `_repsSug` (SER-01): el ÚLTIMO número de las reps del plan ("8-10" → 10). null con AMRAP, ∞ o máx: ahí no hay
     * registro de un toque.
     */
    fun repsDelPlan(reps: String?): Double? {
        if (reps == null) return null
        if (sinTopeRE.prueba(reps)) return null
        val ultimo = numerosRE.todas(reps).lastOrNull() ?: return null
        return Js.parseInt(ultimo, base10 = false)
    }
}

object CamposSerie {
    private val noDecimal = JsRegex("""[^0-9.]""")
    private val punto = JsRegex("""\.""")
    private val noDigito = JsRegex("""[^0-9]""")

    /** `normalizarCampoSerie` (SER-04): en kg la primera coma pasa a punto y queda un solo punto; en reps, solo dígitos. */
    fun normalizar(campo: String, valor: String?): String {
        var v = valor ?: ""
        if (campo == "kg") {
            val coma = v.indexOf(',')
            if (coma >= 0) v = v.substring(0, coma) + "." + v.substring(coma + 1)
            v = noDecimal.reemplazarTodo(v, "")
            val i = v.indexOf('.')
            if (i >= 0) v = v.substring(0, i + 1) + punto.reemplazarTodo(v.substring(i + 1), "")
            return v
        }
        if (campo == "reps") return noDigito.reemplazarTodo(v, "")
        return v
    }

    /** `rirDeSet` (SER-02): "" → null; "0" → 0 (fue al fallo, no "no lo cargó"). */
    fun rir(v: String?): Double? {
        if (v.isNullOrEmpty()) return null
        val n = Js.parseInt(v) ?: return null
        return if (n.isFinite()) n else null
    }

    /** Las leyendas del selector de RIR (0-5). */
    fun leyendaRir(actual: String): String {
        val leyendas = mapOf("0" to "al fallo", "1" to "casi fallo", "2" to "1-2 más", "3" to "3 más", "4" to "4 más", "5" to "muy lejos")
        return if (actual.isEmpty()) "elegí un valor" else leyendas[actual] ?: "undefined"
    }
}

/** "📅 Última vez (ayer / hace n días)": la serie tope de la sesión anterior. */
data class UltimaVez(
    /** "82.5kg × 8 · 3 series" */
    val valor: String,
    /** "ayer", "hace 3 días", "la semana pasada" o la fecha ("04-oct"). */
    val cuando: String,
)

object HistorialEntreno {
    /**
     * `fechaLocalDe`: la fecha local (YYYY-MM-DD) de un `registrado_en`. Una serie de las 22:00 en Argentina ya es
     * "mañana" en UTC: cortar el texto en la T partía una sesión en dos días.
     */
    fun fechaLocal(iso: String?, zona: ZoneId): String {
        val s = Js.verdadero(iso) ?: return ""
        val d = FechaJs.leer(s) ?: return s.split("T")[0]
        return FechaJs.ymd(d, zona)
    }

    /**
     * `_ultimaSerieRef`: la MISMA serie en la última sesión del ejercicio, filtrada por variante cuando la tiene (el
     * sugerido de "Soga" sale del historial de Soga). Las filas viejas sin nota cuentan solo para la opción default.
     * Devuelve el índice en `h` (que viene del más nuevo al más viejo).
     */
    fun ultimaSerie(h: List<RegistroHistorico>, indice: Int, variante: String?, esDefault: Boolean, zona: ZoneId): Int? {
        var candidatas = h.indices.toList()
        Js.verdadero(variante)?.let { v -> candidatas = candidatas.filter { h[it].notas == v || (esDefault && h[it].notas == null) } }
        val primera = candidatas.firstOrNull() ?: return null
        val ultimoDia = fechaLocal(h[primera].registradoEn, zona)
        val delDia = candidatas.filter { fechaLocal(h[it].registradoEn, zona) == ultimoDia }
        return delDia.firstOrNull { h[it].serie == indice + 1 } ?: delDia.firstOrNull()
    }

    /**
     * `suggestedKg`: el kg de la última vez en esta serie. Un 0 no sirve si el ejercicio del plan pide kg (filas viejas
     * de cuando se trataba como "sin peso").
     */
    fun kgSugerido(h: List<RegistroHistorico>, indice: Int, variante: String?, esDefault: Boolean, sinKgPlan: Boolean, zona: ZoneId): String {
        val i = ultimaSerie(h, indice, variante, esDefault, zona) ?: return ""
        val p = h[i].pesoKg ?: return ""
        if (p <= 0 && !sinKgPlan) return ""
        return Js.texto(p)
    }

    /** `suggestedReps`: las reps de la última vez en esta serie. */
    fun repsSugeridas(h: List<RegistroHistorico>, indice: Int, variante: String?, esDefault: Boolean, zona: ZoneId): String {
        val i = ultimaSerie(h, indice, variante, esDefault, zona) ?: return ""
        return h[i].reps?.toString() ?: ""
    }

    /** `lastSessionStr` (SER-08): el récord a superar = la serie más pesada de lo traído (48 filas). */
    fun record(h: List<RegistroHistorico>): String? {
        val top = masPesada(h) ?: return null
        // `top.reps_realizadas || top.reps`: con 0 o null cae a `reps`, que la RPC no trae.
        val reps = top.reps?.takeIf { it != 0 }?.toString() ?: "undefined"
        val rir = top.rir?.let { " · RIR $it" } ?: ""
        val variante = Js.verdadero(top.notas)?.let { " ($it)" } ?: ""
        return "${Js.texto(top.pesoKg)}kg × $reps$rir$variante"
    }

    /** `_recordKg`: el kg más alto (para la pregunta de "2,5× tu récord"). */
    fun recordKg(h: List<RegistroHistorico>): Double = h.fold(0.0) { acc, r -> maxOf(acc, Js.oCero(r.pesoKg)) }

    /** `prevSessionStr`: la sesión anterior (el día más reciente que no es hoy): su serie tope, cuántas series y cuándo. */
    fun ultimaVez(h: List<RegistroHistorico>, ahora: Instant, zona: ZoneId): UltimaVez? {
        if (h.isEmpty()) return null
        fun dia(iso: String): String = FechaJs.leer(iso)?.let { FechaJs.ymd(it, zona) } ?: ""
        val hoy = FechaJs.ymd(ahora, zona)
        val previas = h.filter { dia(it.registradoEn) != hoy }
        val primera = previas.firstOrNull() ?: return null
        val sesion = dia(primera.registradoEn)
        val series = previas.filter { dia(it.registradoEn) == sesion }
        val top = masPesada(series)!!
        val fecha = FechaJs.leer(primera.registradoEn)?.let { FechaJs.diaMes(it, zona) } ?: "Invalid Date"
        val a = FechaJs.diaUtc(hoy)
        val b = FechaJs.diaUtc(sesion)
        val cuando = if (a != null && b != null) {
            val atras = a - b
            when {
                atras <= 1 -> "ayer"
                atras < 7 -> "hace $atras días"
                atras < 14 -> "la semana pasada"
                else -> fecha
            }
        } else {
            fecha
        }
        val reps = top.reps?.toString() ?: "undefined"
        val variante = Js.verdadero(top.notas)?.let { " ($it)" } ?: ""
        val cuantas = if (series.size > 1) " · ${series.size} series" else ""
        return UltimaVez("${Js.texto(top.pesoKg)}kg × $reps$variante$cuantas", cuando)
    }

    /** `h.reduce((a,b) => (b.peso_kg||0) > (a.peso_kg||0) ? b : a, h[0])`: la primera de las más pesadas. */
    internal fun masPesada(h: List<RegistroHistorico>): RegistroHistorico? {
        var top = h.firstOrNull() ?: return null
        for (r in h.drop(1)) if (Js.oCero(r.pesoKg) > Js.oCero(top.pesoKg)) top = r
        return top
    }

    /**
     * `kgHeredable` (SER-03): la serie confirmada más cercana hacia atrás con kg > 0; si no hay, la primera de las otras.
     * Cargás el kg una vez y las siguientes lo arrastran.
     */
    fun kgHeredable(series: List<SerieLocal>, indice: Int): String {
        fun sirve(s: SerieLocal) = s.confirmada && (Js.parseFloat(s.kg) ?: Double.NaN) > 0
        var i = indice - 1
        while (i >= 0) {
            if (i < series.size && sirve(series[i])) return series[i].kg
            i -= 1
        }
        series.forEachIndexed { k, s -> if (k != indice && sirve(s)) return s.kg }
        return ""
    }
}

/** Un texto con una parte en negrita (el `<b>` de la web). */
data class TextoConNegrita(val antes: String, val negrita: String, val despues: String)

/** Cómo se ve una fila de serie (`renderSetRow`). */
data class FilaSerie(
    val confirmada: Boolean,
    /** La primera sin confirmar: la que tiene la pista de un toque. */
    val activa: Boolean,
    val placeholderReps: String,
    val placeholderKg: String,
    /** Lo que muestra el campo de kg ("" sin columna de kg). */
    val kg: String,
    /** Sin columna de kg: el campo es de solo lectura y dice "—". */
    val sinKg: Boolean,
    /** "RIR" + el valor, o "RIR·" sin cargar. */
    val rir: String,
    /** El check habilitado (sin confirmar). Confirmada, el botón es el lápiz. */
    val puedeConfirmar: Boolean,
    /** "Registrar lo que hiciste" o "Registrar lo sugerido" (null si ya está confirmada). */
    val tituloConfirmar: String?,
    /** "✓ Tocá para registrar lo de la última vez · **80kg × 10** — o editá si hiciste otra cosa" */
    val pista: TextoConNegrita?,
    /** "🎯 Primera vez con este ejercicio…" (SER-03): sin historial no hay kg sugerido. */
    val calibracion: String?,
) {
    companion object {
        /**
         * `renderSetRow`. `kgUltimaVez` y `repsUltimaVez` salen del historial con el ejercicio DEL PLAN (variante y regla
         * del 0); `sinKg` es la del ejercicio que se muestra (el sustituto, si hay).
         */
        fun armar(
            s: SerieLocal,
            activa: Boolean,
            sinKg: Boolean,
            repsPlan: String?,
            kgUltimaVez: String,
            repsUltimaVez: String,
            kgHeredable: String,
        ): FilaSerie {
            val repsSug = ReglasEjercicio.repsDelPlan(repsPlan)
            val kgSug = if (sinKg) "" else kgUltimaVez
            val repsMostrar = repsUltimaVez.ifEmpty { repsSug?.let(Js::texto) ?: "" }
            val haySugerido = repsSug != null && (sinKg || kgSug.isNotEmpty())
            val tipeo = s.reps.isNotEmpty() || s.kg.isNotEmpty()
            val her = if (sinKg) "" else kgHeredable
            val puede = if (tipeo) s.reps.isNotEmpty() && (sinKg || s.kg.isNotEmpty() || her.isNotEmpty()) else haySugerido
            val pista = if (!s.confirmada && activa && haySugerido && !tipeo) {
                TextoConNegrita(
                    "✓ Tocá para registrar lo de la última vez · ",
                    if (sinKg) "$repsMostrar reps" else "${kgSug}kg × $repsMostrar",
                    " — o editá si hiciste otra cosa",
                )
            } else {
                null
            }
            val calibracion = if (!s.confirmada && activa && !haySugerido && !tipeo && !sinKg && repsSug != null) {
                "🎯 Primera vez con este ejercicio: elegí un peso con el que llegues a ${repsPlan ?: "null"} reps dejando 1–2 en reserva. Queda de referencia para la próxima."
            } else {
                null
            }
            return FilaSerie(
                confirmada = s.confirmada, activa = activa,
                placeholderReps = repsUltimaVez.ifEmpty { repsPlan ?: "" },
                placeholderKg = if (sinKg) "—" else kgSug.ifEmpty { her },
                kg = if (sinKg) "" else s.kg, sinKg = sinKg,
                rir = "RIR" + s.rir.ifEmpty { "·" },
                puedeConfirmar = if (s.confirmada) true else puede,
                tituloConfirmar = if (s.confirmada) null else if (tipeo) "Registrar lo que hiciste" else "Registrar lo sugerido",
                pista = pista, calibracion = calibracion,
            )
        }
    }
}

object ConfirmacionSerie {
    /**
     * Lo que `confirmarSerie` hace con los campos antes de verificar: sin editar es "cumplí lo de la última vez" (reps de
     * la última vez o el tope del plan, y el kg de la última vez; el RIR NUNCA); sin kg se vacía el kg; con reps y sin kg
     * se hereda el de una serie confirmada. El segundo valor es false si faltan datos: la serie queda como quedó (la web
     * también deja escritas las reps del plan aunque no confirme).
     */
    fun completar(
        serie: SerieLocal,
        sinKg: Boolean,
        repsPlan: String?,
        kgUltimaVez: String,
        repsUltimaVez: String,
        kgHeredable: String,
    ): Pair<SerieLocal, Boolean> {
        var s = serie
        if (s.reps.isEmpty() && s.kg.isEmpty()) {
            val usar = repsUltimaVez.ifEmpty { ReglasEjercicio.repsDelPlan(repsPlan)?.let(Js::texto) ?: "" }
            val kg = if (sinKg) "" else kgUltimaVez
            if (usar.isNotEmpty()) s = s.copy(reps = usar)
            if (!sinKg && kg.isNotEmpty()) s = s.copy(kg = kg)
        }
        if (sinKg) s = s.copy(kg = "")
        if (!sinKg && s.kg.isEmpty() && s.reps.isNotEmpty() && kgHeredable.isNotEmpty()) s = s.copy(kg = kgHeredable)
        return s to !(s.reps.isEmpty() || (!sinKg && s.kg.isEmpty()))
    }
}

/** `_serieVerosimil` (SER-05): lo imposible se rechaza; lo raro se pregunta. */
object Verosimilitud {
    const val REPS_MAX = 300.0
    const val KG_MAX = 2000.0
    const val KG_RARO = 600.0
    const val SALTO_KG = 2.5
    const val SALTO_REPS = 3.0

    sealed interface Resultado {
        data object Ok : Resultado

        /** "Revisá las repeticiones: 1214": se marca la fila y no se registra. */
        data class Rechazada(val aviso: String) : Resultado

        /** "¿Está bien cargado?": registra solo si el cliente dice que sí. */
        data class Preguntar(val pregunta: Pregunta) : Resultado
    }

    fun evaluar(reps: String, kg: String, sinKg: Boolean, recordKg: Double, repsUltimaVez: String, repsPlan: String?): Resultado {
        val r = Js.parseInt(reps) ?: Double.NaN
        val k = if (sinKg) 0.0 else Js.parseFloat(primeraComaAPunto(kg)) ?: Double.NaN
        if (!(r >= 1) || r > REPS_MAX) return Resultado.Rechazada("Revisá las repeticiones: $reps")
        if (!sinKg && (!(k >= 0) || k > KG_MAX)) return Resultado.Rechazada("Revisá el peso: $kg kg")
        val dudas = mutableListOf<String>()
        if (!sinKg && k > KG_RARO) dudas += "${Js.texto(k)} kg"
        if (!sinKg && recordKg >= 10 && k > recordKg * SALTO_KG) dudas += "${Js.texto(k)} kg (tu récord era ${Js.texto(recordKg)} kg)"
        val hist = Js.parseInt(repsUltimaVez) ?: Double.NaN
        val ref = if (hist >= 1) hist else Js.oCero(ReglasEjercicio.repsDelPlan(repsPlan))
        if (ref >= 5 && r > maxOf(30.0, ref * SALTO_REPS)) dudas += "${Js.texto(r)} repeticiones (venías haciendo ${Js.texto(ref)})"
        if (dudas.isEmpty()) return Resultado.Ok
        return Resultado.Preguntar(
            Pregunta(
                titulo = "¿Está bien cargado?", cuerpo = "Vas a registrar ${dudas.joinToString(" y ")}. ¿Lo hiciste así?",
                confirmar = "Sí, registrar", cancelar = "Corregir",
            ),
        )
    }

    /** `String(x).replace(',', '.')`: solo la primera coma. */
    fun primeraComaAPunto(s: String): String {
        val i = s.indexOf(',')
        return if (i < 0) s else s.substring(0, i) + "." + s.substring(i + 1)
    }
}

/**
 * Lo que viaja en la cola (kinds `carga` y `estado`), con el mismo payload que la web (`writeSet`, `writeExerciseStatus`),
 * que `Escrituras` ya sabe ejecutar.
 */
object EscriturasEntreno {
    /**
     * `carga_<dia>_<ex>_<serie>` + la semana: arreglo nativo n.º 1 (en la web, la serie de la semana 5 pisaba en la cola
     * a la de la semana 4 si las dos estaban pendientes).
     */
    fun claveCarga(dia: String, ejercicio: String, indice: Int, semana: Int): String = "carga_${dia}_${ejercicio}_${indice}_s$semana"

    /** `estado_<dia>_<ex>` + la semana (mismo arreglo). */
    fun claveEstado(dia: String, ejercicio: String, semana: Int): String = "estado_${dia}_${ejercicio}_s$semana"

    /**
     * El nombre que se registra (SER-13): el del sustituto si hay; si no, el que ya tenía la serie (si el "solo hoy"
     * expiró y se reabre el día, la RPC es upsert y pisaría el nombre); si no, el del plan.
     */
    fun nombre(sustituto: String?, serie: SerieLocal, plan: String): String = sustituto ?: Js.verdadero(serie.nombreRegistrado) ?: plan

    /**
     * El payload de `carga`: `{sesionId, diaId, semana, datos{…}}`. Peso con coma → punto y `|| 0`; reps `|| 0`; RIR
     * "" → null y "0" → 0; notas = la variante de la serie, o la del ejercicio, o null.
     */
    fun carga(
        sesionId: String?,
        dia: String,
        semana: Int,
        ejercicio: String,
        indice: Int,
        serie: SerieLocal,
        nombre: String,
        varianteEjercicio: String?,
    ): ValorJson {
        val peso = Js.oCero(Js.parseFloat(Verosimilitud.primeraComaAPunto(serie.kg)))
        val reps = Js.oCero(Js.parseInt(serie.reps))
        val notas = Js.verdadero(serie.varianteRegistrada) ?: Js.verdadero(varianteEjercicio)
        return ValorJson.objeto(
            "sesionId" to (Js.verdadero(sesionId)?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "diaId" to ValorJson.Texto(dia),
            "semana" to ValorJson.Numero(semana.toDouble()),
            "datos" to ValorJson.objeto(
                "diaId" to ValorJson.Texto(dia), "ejercicioId" to ValorJson.Texto(ejercicio), "ejercicioNombre" to ValorJson.Texto(nombre),
                "serie" to ValorJson.Numero((indice + 1).toDouble()), "peso" to ValorJson.Numero(peso), "reps" to ValorJson.Numero(reps),
                "rir" to (CamposSerie.rir(serie.rir)?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo),
                "notas" to (notas?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            ),
        )
    }

    /** El payload de `estado`: `{sesionId, semana, diaId, exId, seriesObjetivo, status, manual}`. */
    fun estado(sesionId: String?, semana: Int, dia: String, ejercicio: String, seriesObjetivo: Int, status: String, manual: Boolean): ValorJson =
        ValorJson.objeto(
            "sesionId" to (Js.verdadero(sesionId)?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "semana" to ValorJson.Numero(semana.toDouble()),
            "diaId" to ValorJson.Texto(dia), "exId" to ValorJson.Texto(ejercicio),
            "seriesObjetivo" to ValorJson.Numero(seriesObjetivo.toDouble()),
            "status" to ValorJson.Texto(status), "manual" to ValorJson.Booleano(manual),
        )
}

object EstadosEjercicio {
    /** Los estados que cuentan como hecho. */
    val terminales: Set<String> = setOf("completo", "completo_sin_datos", "saltado")

    /** `checkIfDayCompleted`: hay ejercicios y todos están en un estado terminal. */
    fun diaCompleto(ejercicios: List<String>, estado: (String) -> String): Boolean =
        ejercicios.isNotEmpty() && ejercicios.all { estado(it) in terminales }

    /** El siguiente pendiente después de `id` (ENT-17: al completar uno se abre ese). */
    fun siguientePendiente(ejercicios: List<String>, despuesDe: String, estado: (String) -> String): String? {
        val i = ejercicios.indexOf(despuesDe)
        return ejercicios.drop(i + 1).firstOrNull { estado(it) == "pendiente" }
    }
}

/** Series, reps y volumen del día (la card de cierre y los modales de "Cerrar sesión de hoy"). */
class ResumenDia(ejercicios: List<EjercicioEnSesion>) {
    val series: Int
    val reps: Double

    /** Σ reps × kg, sin redondear (la web muestra `Math.round`). */
    val volumen: Double

    init {
        var series = 0
        var reps = 0.0
        var volumen = 0.0
        for (e in ejercicios) {
            for (s in e.series) {
                if (!s.confirmada) continue
                series += 1
                // `parseInt(s.reps)||0` sin base y `parseFloat(s.kg)||0`, como la web.
                val r = Js.oCero(Js.parseInt(s.reps, base10 = false))
                volumen += r * Js.oCero(Js.parseFloat(s.kg))
                reps += r
            }
        }
        this.series = series
        this.reps = reps
        this.volumen = volumen
    }

    /** `Math.round(tonnage)` */
    val volumenRedondeado: Double get() = jsRound(volumen)

    /** El texto del modal de cierre: "2 series · 18 reps · 1460kg de volumen." */
    val textoCierre: String get() = "$series series · ${Js.texto(reps)} reps · ${Js.texto(volumenRedondeado)}kg de volumen."

    /** El del cierre anticipado: "2 series · 1460kg de volumen · 30 min." (`mins||'—'`: 0 y null son "—"). */
    fun textoCierreAnticipado(minutos: Int?): String =
        "$series series · ${Js.texto(volumenRedondeado)}kg de volumen · ${minutos?.takeIf { it != 0 }?.toString() ?: "—"} min."
}

/** Las fechas como las lee y las escribe la web (`new Date(iso)`, `toLocaleDateString`). */
object FechaJs {
    private val UTC = ZoneOffset.UTC

    /**
     * `new Date(iso)` para lo que manda PostgREST: "2026-10-04T22:32:00+00:00", con fracción de segundo, con Z, con espacio
     * en vez de T. Una fecha sola es UTC; fecha y hora sin zona, hora local. null es "Invalid Date". Como JS, el día se
     * desborda al mes siguiente ("2026-02-31" es el 3 de marzo) y las 24:00 son las 0 del día siguiente.
     */
    fun leer(iso: String): Instant? {
        var i = 0
        fun numero(n: Int): Int? {
            if (i + n > iso.length) return null
            var v = 0
            for (k in i until i + n) {
                val c = iso[k]
                if (c !in '0'..'9') return null
                v = v * 10 + (c - '0')
            }
            i += n
            return v
        }
        fun toma(c: Char): Boolean {
            if (i < iso.length && iso[i] == c) {
                i++
                return true
            }
            return false
        }
        val y = numero(4) ?: return null
        if (!toma('-')) return null
        val mo = numero(2) ?: return null
        if (!toma('-')) return null
        val d = numero(2) ?: return null
        if (mo !in 1..12 || d !in 1..31) return null
        val base = LocalDate.of(y, mo, 1).plusDays((d - 1).toLong())
        if (i == iso.length) return base.atStartOfDay(UTC).toInstant()
        if (!(toma('T') || toma(' '))) return null
        val h = numero(2) ?: return null
        if (!toma(':')) return null
        val mi = numero(2) ?: return null
        var s = 0
        var ms = 0
        if (toma(':')) {
            s = numero(2) ?: return null
            // La fracción va con punto: V8 no lee "10:00:00,123Z" (Invalid Date).
            if (toma('.')) {
                val ini = i
                while (i < iso.length && iso[i] in '0'..'9') i++
                if (i == ini) return null
                ms = (iso.substring(ini, i) + "00").take(3).toInt()   // JS se queda con los milisegundos
            }
        }
        if (h > 24 || mi > 59 || s > 59) return null
        // JS solo acepta las 24 en punto.
        if (h == 24 && (mi != 0 || s != 0 || ms != 0)) return null
        // El desfasaje en segundos; null es "sin zona" (hora local). Se aplica a mano: `ZoneOffset` no pasa de ±18 h.
        var desfasaje: Long? = null
        if (toma('Z')) {
            desfasaje = 0
        } else if (i < iso.length && (iso[i] == '+' || iso[i] == '-')) {
            val signo = if (iso[i] == '+') 1 else -1
            i++
            val zh = numero(2) ?: return null
            var zm = 0
            if (toma(':')) {
                zm = numero(2) ?: return null
            } else if (i < iso.length) {
                zm = numero(2) ?: return null
            }
            desfasaje = signo * (zh * 3600L + zm * 60L)
        }
        if (i != iso.length) return null
        val local = LocalDateTime.of(base, LocalTime.MIDNIGHT).plusHours(h.toLong()).plusMinutes(mi.toLong()).plusSeconds(s.toLong())
        val instante = if (desfasaje != null) {
            Instant.ofEpochSecond(local.toEpochSecond(UTC) - desfasaje)
        } else {
            local.atZone(ZoneId.systemDefault()).toInstant()
        }
        return instante.plusMillis(ms.toLong())
    }

    /** YYYY-MM-DD local (`toLocaleDateString('en-CA')` y el `dayStr` de `prevSessionStr`). */
    fun ymd(d: Instant, zona: ZoneId): String = FechaLocal.hoy(d, zona)

    /** `new Date("YYYY-MM-DD")` en días desde 1970 (UTC): la resta de dos da los días de diferencia. */
    fun diaUtc(ymd: String): Long? {
        val p = ymd.split("-").mapNotNull { it.toIntOrNull() }
        if (p.size != 3) return null
        return try {
            LocalDate.of(p[0], 1, 1).plusMonths((p[1] - 1).toLong()).plusDays((p[2] - 1).toLong()).toEpochDay()
        } catch (_: Exception) {
            null
        }
    }

    /** `toLocaleDateString('es-AR', {day:'2-digit', month:'short'})`: "04-oct", "05-sept". */
    fun diaMes(d: Instant, zona: ZoneId): String = formato("dd-MMM", zona).format(d)

    /**
     * `toLocaleTimeString('es-AR', {hour:'2-digit', minute:'2-digit'})`: "06:05 p. m." (JS cambia el U+202F de ICU por
     * un espacio común).
     */
    fun horaMinutos(d: Instant, zona: ZoneId): String =
        formato("hh:mm a", zona).format(d).replace(' ', ' ').replace(' ', ' ')

    private val ES_AR: Locale = Locale.forLanguageTag("es-AR")

    private fun formato(patron: String, zona: ZoneId): DateTimeFormatter = DateTimeFormatter.ofPattern(patron, ES_AR).withZone(zona)
}
