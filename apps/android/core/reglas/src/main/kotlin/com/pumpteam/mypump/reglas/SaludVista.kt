package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.RecuperacionDia
import com.pumpteam.mypump.modelos.ValorJson

// Lo que muestran las cards de Salud y Recuperación y la escena "Mis datos" (cliente.html:6363-7328), sin la vista: qué
// valor gana cada día, qué caso de la card toca, las frases y los números ya formateados como en la web. Gemelo de
// SaludVista.swift; donde la web hace algo con un valor raro (un null, un texto), acá se hace lo de la web.

/** Un día de una serie de salud, con la mejor fuente de ese día. */
data class PuntoSalud(val fecha: String, val valor: Double, val detalle: ValorJson? = null)

/**
 * Los textos que cambian entre iPhone y Android (`_TXT_SALUD`, cliente.html:6412-6437): "cada uno olvidado es un cliente
 * leyendo la palabra iPhone en un Samsung". La app de Android usa [ANDROID].
 */
data class TextosSalud(
    val app: String,
    val boton: String,
    val dispositivo: String,
    val telefono: String,
    val esteTel: String,
    val sinApp: String,
    val relojes: String,
    val sincroniza: String,
    val desdeApp: String,
    val revocar: String,
) {
    companion object {
        val IOS = TextosSalud(
            app = "Salud de Apple", boton = "Conectar Apple Health", dispositivo = "iPhone y Apple Watch", telefono = "tu iPhone",
            esteTel = "Este iPhone", sinApp = "Este iPhone no tiene Salud de Apple.", relojes = "Apple Watch, Oura, Garmin…",
            sincroniza = "la app Salud del iPhone", desdeApp = "la app de iPhone", revocar = "Ajustes → Privacidad y seguridad → Salud → MyPump",
        )
        val ANDROID = TextosSalud(
            app = "Health Connect", boton = "Conectar Health Connect", dispositivo = "Tu teléfono y tu reloj", telefono = "tu teléfono",
            esteTel = "Este teléfono", sinApp = "Este teléfono no tiene Health Connect. Se instala gratis desde Google Play.",
            relojes = "Galaxy Watch, Mi Band, Garmin, Fitbit…", sincroniza = "Health Connect", desdeApp = "la app del teléfono",
            revocar = "Ajustes → Salud y bienestar → Health Connect → MyPump",
        )
    }
}

object SaludVista {

    // MARK: Prioridad de fuentes (SAL-12)

    /**
     * `_PREF_FUENTE`: el MISMO orden que el motor de recuperación (043:100-104). Los relojes por API directa dan rMSSD
     * real; Apple Health y Health Connect retransmiten; el agregador después; lo tipeado a mano al final.
     */
    fun rangoFuente(f: String?): Int? = when (f) {
        "whoop", "oura", "withings", "polar" -> 0
        "apple_health", "health_connect" -> 1
        "rook" -> 2
        "manual" -> 3
        else -> null
    }

    /** `_saludValor(tipo, fecha)`: el valor de la mejor fuente (en HRV, un rMSSD gana antes de mirar la fuente). */
    fun valor(filas: List<FilaSalud>, tipo: String, fecha: String): Double? {
        fun esRmssd(r: FilaSalud): Int = if (tipo == "hrv_ms" && r.detalle?.get("metrica")?.comoTexto == "rmssd") 0 else 1
        var mejor: FilaSalud? = null
        var clave = Pair(0, 0)
        for (r in filas) {
            if (r.tipo != tipo || r.fecha != fecha) continue
            val k = Pair(esRmssd(r), rangoFuente(r.fuente) ?: 4)
            // Estricto: en empate queda la primera (el sort de JS es estable).
            if (mejor == null || k.first < clave.first || (k.first == clave.first && k.second < clave.second)) {
                mejor = r
                clave = k
            }
        }
        // `Number(rows[0].valor)`: un valor nulo cuenta como 0.
        return mejor?.let { it.valor ?: 0.0 }
    }

    /** `_serieSalud(tipo)`: un punto por fecha con la mejor fuente (en empate, la primera), ordenado por fecha. */
    fun serie(filas: List<FilaSalud>, tipo: String): List<PuntoSalud> {
        val porFecha = HashMap<String, Pair<Int, PuntoSalud>>()
        for (r in filas) {
            if (r.tipo != tipo) continue
            val p = rangoFuente(r.fuente) ?: 9
            val actual = porFecha[r.fecha]
            if (actual != null && p >= actual.first) continue
            porFecha[r.fecha] = p to PuntoSalud(r.fecha, r.valor ?: 0.0, r.detalle)
        }
        return porFecha.keys.sorted().map { porFecha.getValue(it).second }
    }

    /** `_saludTieneReciente(tipos, dias)`: ¿llegó alguno de estos tipos desde hace `dias` días? (`dias || 7`: 0 es 7.) */
    fun tieneReciente(filas: List<FilaSalud>, tipos: List<String>, dias: Int, hoy: String): Boolean {
        val nHoy = DiaCalendario.numero(hoy) ?: return false
        val d = if (dias == 0) 7 else dias
        return filas.any { r ->
            if (r.tipo !in tipos || r.valor == null) return@any false
            val n = DiaCalendario.numero(r.fecha) ?: return@any false
            n >= nHoy - d
        }
    }

    // MARK: Card Salud (SAL-10)

    data class ResumenSalud(
        val pasosHoy: Double?,
        val minutosActivosHoy: Double?,
        val suenoAnoche: Double?,
        val hrv: Double?,
        /** "Promedio N días": los últimos 7 con pasos. */
        val diasPromedio: Int,
        val promedioPasos: Long,
    )

    /** `renderMydaySalud` con datos: null si no hay ni pasos ni minutos activos (la card no muestra números). */
    fun resumen(filas: List<FilaSalud>, hoy: String): ResumenSalud? {
        val pasos = filas.filter { it.tipo == "pasos" }
        if (pasos.isEmpty() && filas.none { it.tipo == "actividad_min" }) return null
        val fechas = pasos.map { it.fecha }.toSet().sorted().takeLast(7)
        val vals = fechas.mapNotNull { valor(filas, "pasos", it) }
        val prom = if (vals.isEmpty()) 0L else jsEntero(vals.fold(0.0) { a, b -> a + b } / vals.size)
        val ayer = DiaCalendario.numero(hoy)?.let { DiaCalendario.texto(it - 1) } ?: hoy
        return ResumenSalud(
            pasosHoy = valor(filas, "pasos", hoy),
            minutosActivosHoy = valor(filas, "actividad_min", hoy),
            suenoAnoche = valor(filas, "sueno_min", hoy) ?: valor(filas, "sueno_min", ayer),
            hrv = valor(filas, "hrv_ms", hoy) ?: valor(filas, "hrv_ms", ayer),
            diasPromedio = vals.size,
            promedioPasos = prom,
        )
    }

    // MARK: Card Recuperación (SAL-09)

    data class Motivo(val sube: Boolean, val antes: String, val negrita: String, val despues: String) {
        val texto: String get() = antes + negrita + despues
    }

    sealed interface CardRecuperacion {
        /** Sin score y sin Salud conectada: explicación + "Conectar …". */
        data object SinConectar : CardRecuperacion

        /** Conectado pero sin score: qué falta (trayendo historial, faltan datos de la noche, solo pasos, no llega nada,
         *  esperando). */
        data class ConectadoSinScore(val sinScore: SinScore) : CardRecuperacion

        /** Aprendiendo la normal del cliente: n de 14 días. */
        data class Calibrando(val dias: Int, val porcentaje: Int, val yaSe: String) : CardRecuperacion

        /** El cliente apagó el número. */
        data object Oculto : CardRecuperacion

        data class ConScore(val score: SaludVista.ConScore) : CardRecuperacion
    }

    sealed interface SinScore {
        data class TrayendoHistorial(val hecho: Int, val total: Int) : SinScore
        data object FaltanDatosDeLaNoche : SinScore
        data object SoloPasos : SinScore
        data object NoLlegaNada : SinScore
        data object Esperando : SinScore

        fun frase(t: TextosSalud = TextosSalud.ANDROID): String = when (this) {
            is TrayendoHistorial -> "Trayendo tu historial de Salud… $hecho/$total días"
            FaltanDatosDeLaNoche -> "Estos días no están llegando los datos de la noche."
            SoloPasos -> "${t.esteTel} ya está mandando pasos y actividad. 👌"
            NoLlegaNada -> "Salud está conectada pero no llegó ningún dato."
            Esperando -> "Conectado. Esperando los primeros datos de ${t.telefono}…"
        }

        /**
         * La nota de abajo. En "no llega nada" la web escribe la ruta del iPhone también en Android (cliente.html:6674,
         * sin `_T('revocar')`); acá va la de cada plataforma, que es la que existe en ese teléfono.
         */
        fun nota(t: TextosSalud = TextosSalud.ANDROID): String = when (this) {
            is TrayendoHistorial -> "Puede tardar un rato la primera vez. Podés seguir usando la app."
            FaltanDatosDeLaNoche -> "Fijate que el reloj esté sincronizando con ${t.sincroniza}."
            SoloPasos -> "Para el score de recuperación hace falta lo que se mide durmiendo — pulso en reposo, sueño y variabilidad — " +
                "y eso lo da un reloj o un anillo (${t.relojes}). En cuanto uses uno, esto se arma solo."
            NoLlegaNada -> "Fijate que esté todo activado en ${t.revocar}."
            Esperando -> "Si tenés reloj o anillo, con eso el score arranca mucho más rápido."
        }
    }

    data class ConScore(
        val fila: RecuperacionDia,
        /** alta | media | baja */
        val banda: String,
        /** "Recuperado" | "Medio" | "Poco recuperado" */
        val bandaTexto: String,
        val frase: String?,
        val motivos: List<Motivo>,
        /** "Score de lunes: la de anoche todavía no llegó." cuando se muestra uno de los 3 días anteriores. */
        val notaVieja: String?,
        val provisoria: Boolean,
        /** El gráfico de 14 días (los puntos con score; hacen falta 3). */
        val grafico: List<Pair<String, Int>>,
    )

    val textoBanda: Map<String, String> = mapOf("alta" to "Recuperado", "media" to "Medio", "baja" to "Poco recuperado")

    /**
     * `renderMydayRecuperacion`: qué caso de la card toca. La serie viene densa (una fila por día) y la última es hoy en
     * hora argentina: se muestra el último score REAL de los últimos 3 días.
     */
    fun cardRecuperacion(
        serie: List<RecuperacionDia>,
        conectado: Boolean,
        mostrar: Boolean,
        salud: List<FilaSalud>,
        historial: Pair<Int, Int>?,
        sinDatos: Boolean,
        hoy: String,
    ): CardRecuperacion {
        val ultima = serie.lastOrNull()
        val conScore = serie.takeLast(3).reversed().firstOrNull { it.score != null }
        val fila = conScore ?: ultima
        if (fila == null || fila.estado == "insuficiente") {
            if (!conectado) return CardRecuperacion.SinConectar
            return CardRecuperacion.ConectadoSinScore(sinScore(salud, historial, sinDatos, hoy))
        }
        if (fila.estado == "calibrando" || fila.score == null) {
            // `row.dias_datos || 0` y `Math.min(100, Math.round(n / 14 * 100))`.
            val n = fila.diasDatos ?: 0
            val pct = minOf(100L, jsEntero(n / 14.0 * 100)).toInt()
            val cob = fila.cobertura
            val sueno = cob?.get("sueno_min")
            val fc = cob?.get("fc_reposo")
            val ya = when {
                cob is ValorJson.Objeto && SemanticaJs.esVerdadero(sueno) -> "Ya sé que dormís cerca de ${horasSinEspacio(SemanticaJs.numero(sueno))}."
                cob is ValorJson.Objeto && SemanticaJs.esVerdadero(fc) -> "Ya sé que tu pulso en reposo ronda los ${enteroJS(SemanticaJs.numero(fc))}."
                else -> ""
            }
            return CardRecuperacion.Calibrando(n, pct, ya)
        }
        if (!mostrar) return CardRecuperacion.Oculto

        val banda = fila.banda ?: "media"
        val motivos = motivos(fila)
        val frase = when {
            fila.discordancia == true -> "Los números dicen una cosa y vos me dijiste otra. Le creo a lo que sentís."
            fila.estadoAutonomico == "maladaptacion" -> "Tu cuerpo viene peleando con la carga. Hoy conviene aflojar."
            fila.estadoAutonomico == "fatiga_acumulada" -> "Venís con fatiga acumulada de varios días."
            motivos.isEmpty() -> when (banda) {
                "alta" -> "Venís bien. Aprovechalo."
                "baja" -> "Hoy tu cuerpo pide más descanso."
                else -> "Estás en tu rango normal."
            }
            else -> null
        }
        // `conScore !== ultima`: la fila mostrada no es la de hoy.
        val vieja = conScore != null && ultima != null && conScore !== ultima
        val puntos = serie.mapNotNull { r -> r.score?.let { r.fecha to it } }
        return CardRecuperacion.ConScore(
            ConScore(
                fila = fila, banda = banda, bandaTexto = textoBanda[banda] ?: "", frase = frase, motivos = motivos,
                notaVieja = if (vieja) "Score de ${diaDeLaSemana(fila.fecha)}: la de anoche todavía no llegó." else null,
                provisoria = fila.bandaProvisoria == true,
                grafico = if (puntos.size >= 3) puntos else emptyList(),
            ),
        )
    }

    /** `_recupSinScoreConectado`: lo que separa los casos es qué está llegando, no cuánto falta. */
    fun sinScore(salud: List<FilaSalud>, historial: Pair<Int, Int>?, sinDatos: Boolean, hoy: String): SinScore {
        if (historial != null) return SinScore.TrayendoHistorial(historial.first, historial.second)
        val nocturnos = listOf("fc_reposo", "hrv_ms", "sueno_min")
        val nocheReciente = tieneReciente(salud, nocturnos, 7, hoy)
        val nocheAlguna = tieneReciente(salud, nocturnos, 60, hoy)
        val diaReciente = tieneReciente(salud, listOf("pasos", "actividad_min", "kcal_activas"), 7, hoy)
        if (!nocheReciente && nocheAlguna) return SinScore.FaltanDatosDeLaNoche
        if (diaReciente) return SinScore.SoloPasos
        if (sinDatos) return SinScore.NoLlegaNada
        return SinScore.Esperando
    }

    /**
     * `_recDrivers`: hasta 3 motivos (de los 3 primeros), del hecho a castellano. Los tipos que no se conocen se saltean.
     * Con la aritmética de JS: un `valor` null es 0 ("Dormiste 0h00"), uno ausente NaN, y `baseline` cuenta si es
     * verdadero.
     */
    fun motivos(fila: RecuperacionDia): List<Motivo> {
        val ms = (fila.motivos as? ValorJson.Lista)?.elementos ?: return emptyList()
        return ms.take(3).mapNotNull { m ->
            val sube = SemanticaJs.numero(m["dir"]) > 0
            val v = SemanticaJs.numero(m["valor"])
            val base = m["baseline"]
            val conBase = SemanticaJs.esVerdadero(base)
            when (m["tipo"]?.comoTexto) {
                "sueno" -> Motivo(sube, "Dormiste ", horasSinEspacio(v), if (conBase) " · venís de ${horasSinEspacio(SemanticaJs.numero(base))}" else "")
                "fc_reposo" -> {
                    val d = if (conBase) jsRound(Math.abs(v - SemanticaJs.numero(base))) else 0.0
                    Motivo(sube, "Pulso en reposo ", enteroJS(v), if (SemanticaJs.verdadero(d)) " · ${enteroJS(d)} más que tu normal" else "")
                }
                "hrv" -> Motivo(sube, "Variabilidad ", "${enteroJS(v)} ms", if (conBase) " · tu normal es ${enteroJS(SemanticaJs.numero(base))}" else "")
                "carga" -> Motivo(sube, "Entrenaste fuerte: ", SemanticaJs.plantilla(m["agudo"]), " series duras en 3 días")
                "regularidad" -> Motivo(sube, "Horarios de sueño irregulares esta semana", "", "")
                else -> null
            }
        }
    }

    // MARK: Mis datos (SAL-11)

    data class Componente(
        val clave: String,
        val nombre: String,
        val score: Long,
        /** Lo que pesa en el score, sobre el total de los componentes presentes. */
        val aporte: Long,
    )

    val nombresComponentes: List<Pair<String, String>> = listOf(
        "autonomico" to "Corazón (pulso + variabilidad)", "sueno" to "Sueño", "carga" to "Carga del gimnasio",
        "subjetivo" to "Cómo te sentís", "otros" to "Respiración, oxígeno, temperatura",
    )

    /**
     * "Cómo se arma tu recuperación": los pesos del motor vienen sin normalizar (45/25/20/12/8) y se reparten sobre los
     * presentes, que es el aporte real. Presente es `comp[k] && comp[k].score != null`, como en la web.
     */
    fun componentes(fila: RecuperacionDia?): List<Componente> {
        if (fila == null || fila.score == null) return emptyList()
        val comp = fila.componentes as? ValorJson.Objeto ?: return emptyList()
        fun presente(c: ValorJson?): Boolean = SemanticaJs.esVerdadero(c) && c?.get("score").let { it != null && it != ValorJson.Nulo }
        val presentes = nombresComponentes.filter { presente(comp[it.first]) }
        // `(Number(comp[k].peso) || 0)` y `|| 1` si suman 0.
        val wTot = presentes.fold(0.0) { a, k -> a + Js.oCero(SemanticaJs.numero(comp[k.first]?.get("peso"))) }
        val total = Js.oCero(wTot).let { if (it == 0.0) 1.0 else it }
        return presentes.map { (clave, nombre) ->
            val c = comp[clave]
            Componente(clave, nombre, jsEntero(SemanticaJs.numero(c?.get("score"))), jsEntero(Js.oCero(SemanticaJs.numero(c?.get("peso"))) / total * 100))
        }
    }

    /**
     * Una fila de métrica de "Mis datos" (`_filaSalud`): el valor del último día, el promedio de 7 y de 30 y la flecha
     * contra el de 30 si se aparta más de un 3 %.
     */
    data class FilaMetrica(
        val tipo: String,
        val valor: String,
        val delta: String?,
        val deltaEsBueno: Boolean,
        val promedio7: String,
        val promedio30: String?,
        val diasConDato: Int,
        val serie: List<PuntoSalud>,
    )

    fun fila(filas: List<FilaSalud>, tipo: String, mejorSube: Boolean = true, formato: (Double) -> String = entero): FilaMetrica? {
        val s = serie(filas, tipo)
        val ultimo = s.lastOrNull() ?: return null
        val p7 = promedio(s.takeLast(7).map { it.valor })
        val p30 = promedio(s.takeLast(30).map { it.valor })
        var delta: String? = null
        var bueno = true
        if (p30 != null && Math.abs(ultimo.valor - p30) / (if (SemanticaJs.verdadero(p30)) p30 else 1.0) > 0.03) {
            val sube = ultimo.valor > p30
            bueno = if (mejorSube) sube else !sube
            delta = "${if (sube) "↑" else "↓"} ${formato(Math.abs(ultimo.valor - p30))}"
        }
        return FilaMetrica(
            tipo = tipo, valor = formato(ultimo.valor), delta = delta, deltaEsBueno = bueno,
            promedio7 = p7?.let(formato) ?: "", promedio30 = if (s.size > 7) p30?.let(formato) else null,
            diasConDato = s.size, serie = s,
        )
    }

    data class Regularidad(val horaDormirse: String, val variacion: Long, val texto: String)

    /** Regularidad del sueño: hora promedio de dormirse (punto medio − 3 h 30) y variación, con 4 noches o más. */
    fun regularidad(filas: List<FilaSalud>): Regularidad? {
        val s = serie(filas, "sueno_medio_min")
        if (s.size < 4) return null
        val (m, sd) = promedioCircular(s.takeLast(7).map { it.valor })
        val texto = if (sd <= 30) "Muy regular — eso ayuda tanto como dormir más."
        else if (sd >= 90) "Bastante irregular: acostarte a horarios parecidos mueve la aguja." else "Razonablemente regular."
        return Regularidad(horaReloj(m - 210), jsEntero(sd), texto)
    }

    /** "Anoche" / "Anteanoche" / "Noche del 12 oct" para la última noche con dato. */
    fun rotuloNoche(fecha: String, hoy: String): String {
        val n = DiaCalendario.numero(fecha) ?: return "Anoche"
        val h = DiaCalendario.numero(hoy) ?: return "Anoche"
        if (n == h) return "Anoche"
        if (n == h - 1) return "Anteanoche"
        val corta = fechaCorta(fecha) ?: return "Última noche con dato"
        return "Noche del $corta"
    }

    /** `toLocaleDateString('es-AR', {day: 'numeric', month: 'short'})` de una fecha "YYYY-MM-DD": "12 oct". */
    fun fechaCorta(fecha: String): String? {
        val partes = fecha.take(10).split("-").filter { it.isNotEmpty() }.mapNotNull { enteroSwift(it) }
        if (partes.size != 3 || partes[1] !in 1L..12L) return null
        return "${partes[2]} ${meses[(partes[1] - 1).toInt()]}"
    }

    // MARK: Formatos (como los de la web)

    internal val meses = listOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic")
    internal val diasSemana = listOf("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")

    /** `toLocaleDateString('es-AR', {weekday: 'long'})` de una fecha "YYYY-MM-DD". */
    fun diaDeLaSemana(fecha: String): String {
        val n = DiaCalendario.numero(fecha) ?: return "la última noche con datos"
        return diasSemana[Math.floorMod(n + 4, 7L).toInt()]   // 1970-01-01 fue jueves
    }

    /** `_fmtHs`: "7h05" (la card de recuperación). */
    fun horasSinEspacio(m: Double): String = "${enteroJS(Math.floor(m / 60))}h${dosCifras(jsRound(m % 60))}"

    /** `fmtSueno` / `hs`: "7h 05" (Salud y Mis datos). */
    fun horas(m: Double): String = "${enteroJS(Math.floor(m / 60))}h ${dosCifras(jsRound(m % 60))}"

    /** `String(Math.round(x))`: "NaN" e "Infinity" como JS, y 1e21 como "1e+21". */
    fun enteroJS(x: Double): String = NumeroJs.texto(jsRound(x))

    /**
     * `Math.round(v).toLocaleString('es-AR')`: "8.548". Como ICU, con los dígitos más cortos que vuelven al número (1e23
     * es "100.000.000.000.000.000.000.000"), "-0" para un −0 e "∞" para el infinito.
     */
    fun miles(v: Double): String {
        if (v.isNaN()) return "NaN"
        if (v.isInfinite()) return if (v > 0) "∞" else "-∞"
        val r = jsRound(v)
        val s = digitosDeEntero(Math.abs(r))
        val out = StringBuilder()
        for ((i, c) in s.reversed().withIndex()) {
            if (i > 0 && i % 3 == 0) out.append('.')
            out.append(c)
        }
        val negativo = r < 0 || (r == 0.0 && 1.0 / r < 0)
        return (if (negativo) "-" else "") + out.reverse().toString()
    }

    /** Los dígitos de un entero no negativo como los da `toLocaleString` (los más cortos, completados con ceros). */
    private fun digitosDeEntero(x: Double): String {
        val t = NumeroJs.texto(x)
        val e = t.indexOf("e+")
        if (e < 0) return t
        val mantisa = t.substring(0, e)
        val decimales = mantisa.substringAfter('.', "").length
        return mantisa.replace(".", "") + "0".repeat(t.substring(e + 2).toInt() - decimales)
    }

    val entero: (Double) -> String = { enteroJS(it) }

    /** `v.toFixed(1)` (el punto queda: así se ve en la web). */
    val unDecimal: (Double) -> String = { toFixed(it, 1) }

    /** `_hhmmReloj`: minutos (puede ser negativo o pasar de 1440) → "HH:MM". */
    fun horaReloj(mm: Double): String {
        if (!mm.isFinite()) return "NaN:NaN"
        // `%` de JS es el resto exacto del double: primero el resto, después el entero (que así siempre entra).
        val r = (jsRound(mm) % 1440).toInt()
        val x = ((r % 1440) + 1440) % 1440
        return String.format(java.util.Locale.ROOT, "%02d:%02d", x / 60, x % 60)
    }

    /** `_promCircularMin`: promedio circular de minutos del día y desvío plegado a ±720. */
    fun promedioCircular(vals: List<Double>): Pair<Double, Double> {
        val v = vals.filter { it.isFinite() }
        if (v.isEmpty()) return 0.0 to 0.0
        val ang = v.map { it / 1440 * 2 * Math.PI }
        val cx = ang.fold(0.0) { a, t -> a + Math.cos(t) } / ang.size
        val cy = ang.fold(0.0) { a, t -> a + Math.sin(t) } / ang.size
        var a = Math.atan2(cy, cx)
        if (a < 0) a += 2 * Math.PI
        val m = a / (2 * Math.PI) * 1440
        val dev = v.map { x ->
            var d = (x - m) % 1440
            if (d > 720) d -= 1440
            if (d < -720) d += 1440
            d
        }
        return m to Math.sqrt(dev.fold(0.0) { s, d -> s + d * d } / dev.size)
    }

    internal fun promedio(xs: List<Double>): Double? = if (xs.isEmpty()) null else xs.fold(0.0) { a, b -> a + b } / xs.size

    /** `String(x).padStart(2, '0')` de un número entero. */
    internal fun dosCifras(x: Double): String = NumeroJs.texto(x).padStart(2, '0')

    /** `Int(s)` de Swift para las partes de una fecha: signo opcional y dígitos ASCII. */
    private fun enteroSwift(s: String): Long? {
        val inicio = if (s.startsWith("+") || s.startsWith("-")) 1 else 0
        if (inicio == s.length || (inicio until s.length).any { s[it] !in '0'..'9' }) return null
        return s.toLongOrNull()
    }
}

/**
 * `Math.round` de JS como entero, sin riesgo (`jsEntero` de iOS): NaN o infinito valen 0 y lo de más de ±10^15 se acota.
 */
fun jsEntero(x: Double): Long {
    val r = jsRound(x)
    if (!r.isFinite()) return 0
    return maxOf(-1e15, minOf(1e15, r)).toLong()
}
