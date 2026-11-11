package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlin.math.floor

/**
 * Reglas puras de «Presión arterial» (`presion/CONTRATO_APP.md`). Gemelo de `public/js/presion.js` (la referencia) y de
 * Presion.swift: `apps/shared/vectores/presion.json` hace fallar las pruebas si difieren.
 *
 * Invariantes:
 * · El alumno no ve promedios, colores, categorías ni palabras como hipertensión, normal, alta o riesgo. Lo que calcula
 *   [resumenSerie] no se muestra: solo el avance.
 * · La presión nunca frena el entrenamiento: nada de acá toca la rutina.
 * · El texto de guardia se decide acá, sin esperar al servidor.
 */
object Presion {
    object Lim {
        const val SIS_MIN = 60
        const val SIS_MAX = 260
        const val DIA_MIN = 30
        const val DIA_MAX = 160
        const val PUL_MIN = 25
        const val PUL_MAX = 220
        const val DIF_MIN = 10
    }

    const val ESPERA_REPETICION_S = 300
    const val REPOSO_S = 300
    const val RECORDATORIO_MIN = 10

    /** Minutos sin repetir una toma de 180/120 para que cuente como alta (el recordatorio sale a los 10). */
    const val SIN_REPETIR_MIN = 15

    val alarma = listOf("dolor_pecho", "falta_aire", "cefalea_fuerte_nueva", "cambios_vista", "debilidad_un_lado", "dificultad_hablar", "confusion", "desmayo")
    val otros = listOf("palpitaciones", "mareo_al_pararse", "vomitos_diarrea")

    // ── Tipos ──

    data class Toma(
        val orden: Int,
        /** "sentado", "acostado" o "de_pie". Sin dato vale sentado. */
        val posicion: String? = "sentado",
        val minutosDePie: Int? = null,
        val brazo: String? = null,
        val sis: Int,
        val dia: Int,
        val pulso: Int,
        val latidoIrregular: Boolean = false,
        val medidoEn: String? = null,
        val confirmadaPorAlumno: Boolean = false,
    ) {
        val sentado: Boolean get() = posicion == "sentado" || posicion.isNullOrEmpty()

        fun aValor(): ValorJson = ValorJson.objeto(
            "orden" to n(orden), "posicion" to t(posicion), "minutos_de_pie" to n(minutosDePie), "brazo" to t(brazo), "sis" to n(sis), "dia" to n(dia),
            "pulso" to n(pulso), "latido_irregular" to ValorJson.Booleano(latidoIrregular), "medido_en" to t(medidoEn),
            "confirmada_por_alumno" to ValorJson.Booleano(confirmadaPorAlumno),
        )

        companion object {
            /** Tolerante: sin alta, baja o pulso enteros no hay toma; lo demás vale lo de fábrica. */
            fun desde(j: ValorJson): Toma? {
                val s = entero(j["sis"]) ?: return null
                val d = entero(j["dia"]) ?: return null
                val p = entero(j["pulso"]) ?: return null
                return Toma(
                    orden = entero(j["orden"]) ?: 1, posicion = j["posicion"]?.comoTexto, minutosDePie = entero(j["minutos_de_pie"]), brazo = j["brazo"]?.comoTexto,
                    sis = s, dia = d, pulso = p, latidoIrregular = j["latido_irregular"] == ValorJson.Booleano(true), medidoEn = j["medido_en"]?.comoTexto,
                    confirmadaPorAlumno = j["confirmada_por_alumno"] == ValorJson.Booleano(true),
                )
            }
        }
    }

    data class Previo(val cafeina: Boolean = false, val fumo: Boolean = false, val comida: Boolean = false, val ejercicio: Boolean = false) {
        val alguno: Boolean get() = cafeina || fumo || comida || ejercicio

        fun aValor(): ValorJson = ValorJson.objeto(
            "cafeina" to ValorJson.Booleano(cafeina), "fumo" to ValorJson.Booleano(fumo), "comida" to ValorJson.Booleano(comida), "ejercicio" to ValorJson.Booleano(ejercicio),
        )
    }

    /** Una sesión de medición: lo que evalúa [evaluarSesion] y lo que se manda a `mypump_presion_sesion`. */
    data class Sesion(
        val id: String? = null,
        val serieId: String? = null,
        /** "estandar", "bajo_efecto", "suelta", "ortostatica" o "comparacion_brazos". */
        val tipo: String = "estandar",
        val inicio: String? = null,
        val zonaHoraria: String? = null,
        val brazo: String? = null,
        val previo: Previo = Previo(),
        val reposoCumplido: Boolean? = null,
        val temporizadorSalteado: Boolean? = null,
        val dosisEstimulanteHora: String? = null,
        val entrenoEntreDosisYToma: Boolean? = null,
        val sintomas: List<String> = emptyList(),
        /** null sin contestar, "si" con algún Sí, "no" con todos en No. */
        val listaEspera: String? = null,
        val nota: String? = null,
        /** Minutos desde la última toma: solo para evaluar, no viaja. */
        val minutosDesdeUltima: Double = 0.0,
        val tomas: List<Toma> = emptyList(),
        /** Día local "AAAA-MM-DD" y orden dentro del día: los usa [resumenSerie]. */
        val fecha: String? = null,
        val orden: Int? = null,
    ) {
        /** Con las claves del servidor (guion bajo): para guardarla en el teléfono. Lo que viaja lo arma el modelo. */
        fun aValor(): ValorJson = ValorJson.objeto(
            "id" to t(id), "serie_id" to t(serieId), "tipo" to ValorJson.Texto(tipo), "inicio" to t(inicio), "zona_horaria" to t(zonaHoraria), "brazo" to t(brazo),
            "previo" to previo.aValor(), "reposo_cumplido" to b(reposoCumplido), "temporizador_salteado" to b(temporizadorSalteado),
            "dosis_estimulante_hora" to t(dosisEstimulanteHora), "entreno_entre_dosis_y_toma" to b(entrenoEntreDosisYToma),
            "sintomas" to ValorJson.Lista(sintomas.map { ValorJson.Texto(it) }), "lista_espera" to t(listaEspera), "nota" to t(nota),
            "tomas" to ValorJson.Lista(tomas.map { it.aValor() }), "fecha" to t(fecha), "orden" to n(orden),
        )

        companion object {
            /** Con la forma de los vectores y del servidor (claves con guion bajo). */
            fun desde(j: ValorJson): Sesion {
                val p = j["previo"]
                fun si(k: String) = p?.get(k) == ValorJson.Booleano(true)
                return Sesion(
                    id = j["id"]?.comoTexto, serieId = j["serie_id"]?.comoTexto, tipo = j["tipo"]?.comoTexto ?: "estandar", inicio = j["inicio"]?.comoTexto,
                    zonaHoraria = j["zona_horaria"]?.comoTexto, brazo = j["brazo"]?.comoTexto,
                    previo = Previo(si("cafeina"), si("fumo"), si("comida"), si("ejercicio")),
                    reposoCumplido = booleano(j["reposo_cumplido"]), temporizadorSalteado = booleano(j["temporizador_salteado"]),
                    dosisEstimulanteHora = j["dosis_estimulante_hora"]?.comoTexto, entrenoEntreDosisYToma = booleano(j["entreno_entre_dosis_y_toma"]),
                    sintomas = lista(j["sintomas"]).mapNotNull { it.comoTexto }, listaEspera = j["lista_espera"]?.comoTexto, nota = j["nota"]?.comoTexto,
                    minutosDesdeUltima = j["minutos_desde_ultima"]?.comoNumero ?: 0.0, tomas = lista(j["tomas"]).mapNotNull(Toma::desde),
                    fecha = j["fecha"]?.comoTexto, orden = entero(j["orden"]),
                )
            }
        }
    }

    data class Aparato(
        val id: String? = null,
        /** "brazo", "muneca" o "reloj_anillo_otro". */
        val tipo: String?,
        val marca: String? = null,
        val modelo: String? = null,
        val modeloCodigo: String? = null,
        val manguitoMinCm: Double? = null,
        val manguitoMaxCm: Double? = null,
        val manguitoValidadoMinCm: Double? = null,
        val manguitoValidadoMaxCm: Double? = null,
        /** "si", "no" o "sin_revisar". */
        val validado: String? = null,
    ) {
        companion object {
            fun desde(j: ValorJson?): Aparato? {
                if (j !is ValorJson.Objeto) return null
                return Aparato(
                    id = j["id"]?.comoTexto, tipo = j["tipo"]?.comoTexto, marca = j["marca"]?.comoTexto, modelo = j["modelo"]?.comoTexto,
                    modeloCodigo = j["modelo_codigo"]?.comoTexto, manguitoMinCm = j["manguito_min_cm"]?.comoNumero, manguitoMaxCm = j["manguito_max_cm"]?.comoNumero,
                    manguitoValidadoMinCm = j["manguito_validado_min_cm"]?.comoNumero, manguitoValidadoMaxCm = j["manguito_validado_max_cm"]?.comoNumero,
                    validado = j["validado"]?.comoTexto,
                )
            }
        }
    }

    enum class Validez(val clave: String) { OK("ok"), IMPOSIBLE("imposible"), CONFIRMAR("confirmar") }
    enum class Nivel(val clave: String) { COMUN("comun"), ALTA("alta"), URGENCIA("urgencia") }

    data class Metodo(
        /** "brazo", "muneca_provisoria", "muneca_habitual" o "no_sirve". */
        val metodo: String = "brazo",
        val provisoria: Boolean = false,
        val pedirBrazo: Boolean = false,
        val pedirValidado: Boolean = false,
        val admiteTomas: Boolean = true,
    )

    data class PasoGuiado(val esperaS: Int, val posicion: String, val minutosDePie: Int?, val brazo: String?)

    data class Ortostatica(val caidaSisMax: Int, val caidaDiaMax: Int, val subidaPulsoMax: Int, val hipotension: Boolean, val hipertensionPosible: Boolean)

    data class Valor(val sis: Int, val dia: Int, val pulso: Int)

    enum class Paso(val clave: String) {
        LISTO("listo"), REPETIR("repetir"), REPETIR_CON_LISTA("repetir_con_lista"), GUARDIA_PRESION("guardia_presion"), GUARDIA_SINTOMAS("guardia_sintomas"),
    }

    data class Evaluacion(
        val paso: Paso,
        /**
         * "ninguno", "guardia_sintomas", "guardia_presion", "repetir_pendiente", "lista_sintomas_espera", "quedate_sentado_5min",
         * "sentate_agua", "quedate_sentado_ortostatica" o "toma_no_cuenta".
         */
        val texto: String,
        val cuenta: Boolean,
        val motivoExclusion: String?,
        val valor: Valor?,
        val validaBajoEfecto: Boolean,
        val urgencia: Boolean,
        val ortostatica: Ortostatica?,
        val reglas: List<String>,
    )

    data class EntradaSerie(
        val tipo: String? = null,
        val tomasObjetivo: Int? = null,
        val fechaInicio: String? = null,
        val sesiones: List<Sesion> = emptyList(),
        val soloUrgencias: Boolean = false,
        val basalPulso: Int? = null,
    )

    data class BajoEfecto(val n: Int, val validas: Int, val promedio: Valor?, val tomasPulso100OMas: Int, val aviso: Boolean, val alta: Boolean)

    /** Lo calcula el teléfono igual que el servidor, pero el alumno solo ve `faltan` y `dias`. */
    data class ResumenSerie(
        val tomasValidas: Int,
        val dias: List<String>,
        val serieValida: Boolean,
        val faltan: Int,
        val promedio: Valor?,
        val maximos: Pair<Int, Int>?,
        val categoria: String?,
        val bajoEfecto: BajoEfecto,
        val reglas: List<String>,
    )

    // ── Ayudas ──

    private fun t(s: String?): ValorJson = s?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo
    private fun b(x: Boolean?): ValorJson = x?.let { ValorJson.Booleano(it) } ?: ValorJson.Nulo
    private fun n(x: Int?): ValorJson = x?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo

    private fun enteroDe(x: Double?): Int? = if (x != null && x.isFinite() && x == floor(x) && abs(x) < 1_000_000_000) x.toInt() else null
    fun entero(j: ValorJson?): Int? = enteroDe((j as? ValorJson.Numero)?.valor)
    private fun booleano(j: ValorJson?): Boolean? = (j as? ValorJson.Booleano)?.valor
    private fun lista(j: ValorJson?): List<ValorJson> = (j as? ValorJson.Lista)?.elementos ?: emptyList()

    /** Promedio redondeado al entero, la mitad para arriba, con cuentas enteras (igual en todos los lenguajes). */
    fun media(xs: List<Int>): Int {
        val n = xs.size
        if (n == 0) return 0
        // Como `Math.floor`: hacia abajo también con negativos.
        return Math.floorDiv(2L * xs.sumOf { it.toLong() } + n, 2L * n).toInt()
    }

    // ── Reglas ──

    /**
     * OK, IMPOSIBLE (no se acepta) o CONFIRMAR (valor de urgencia o de alta: se pide confirmar el número). Los valores llegan como
     * los tecleó el alumno: uno que falta o que no es entero es imposible.
     */
    fun validarToma(sis: Double?, dia: Double?, pulso: Double?): Validez {
        val s = enteroDe(sis) ?: return Validez.IMPOSIBLE
        val d = enteroDe(dia) ?: return Validez.IMPOSIBLE
        val p = enteroDe(pulso) ?: return Validez.IMPOSIBLE
        if (s < Lim.SIS_MIN || s > Lim.SIS_MAX || d < Lim.DIA_MIN || d > Lim.DIA_MAX || p < Lim.PUL_MIN || p > Lim.PUL_MAX) return Validez.IMPOSIBLE
        if (s - d < Lim.DIF_MIN) return Validez.IMPOSIBLE
        if (s >= 160 || d >= 100 || p >= 120 || p <= 40) return Validez.CONFIRMAR
        return Validez.OK
    }

    fun validarToma(sis: Int?, dia: Int?, pulso: Int?): Validez = validarToma(sis?.toDouble(), dia?.toDouble(), pulso?.toDouble())

    /** URGENCIA (180 o 120), ALTA (160 o 100) o COMUN. */
    fun nivelToma(sis: Int, dia: Int): Nivel = when {
        sis >= 180 || dia >= 120 -> Nivel.URGENCIA
        sis >= 160 || dia >= 100 -> Nivel.ALTA
        else -> Nivel.COMUN
    }

    fun deAlarma(codigos: List<String>): Boolean = codigos.any { it in alarma || it == "desmayo_en_esfuerzo" }

    /** El tramo de la barra de talles. Justo en el límite, el de arriba. */
    fun tramoBrazo(cm: Double?): String? = when {
        cm == null || !(cm > 0) -> null
        cm < 22 -> "menos_22"
        cm < 32 -> "estandar"
        cm < 42 -> "grande"
        cm <= 52 -> "extra_grande"
        else -> "mas_52"
    }

    /** true, false, o null si el aparato no trae ningún rango. Manda el validado; si no hay, el impreso. */
    fun manguitoCalza(cm: Double?, a: Aparato?): Boolean? {
        if (a == null || cm == null || !(cm > 0)) return null
        var min = a.manguitoValidadoMinCm
        var max = a.manguitoValidadoMaxCm
        if (min == null || max == null) {
            min = a.manguitoMinCm
            max = a.manguitoMaxCm
        }
        if (min == null || max == null) return null
        if (cm < min || cm > max) return false
        // En el límite entre dos talles, el más grande: un manguito que termina en 32 o en 42 no calza justo ahí.
        if (cm == max && (max == 32.0 || max == 42.0)) return false
        return true
    }

    /** Qué lugar tiene el aparato con esa medida: brazo, muñeca provisoria o muñeca habitual (más de 52 cm). */
    fun metodo(cm: Double?, a: Aparato?): Metodo {
        if (a == null) return Metodo()
        if (a.tipo == "reloj_anillo_otro") return Metodo(metodo = "no_sirve", admiteTomas = false, pedirBrazo = true)
        if (a.tipo == "muneca") {
            return if (cm != null && cm > 52) Metodo(metodo = "muneca_habitual", pedirValidado = a.validado == "no")
            else Metodo(metodo = "muneca_provisoria", provisoria = true, pedirBrazo = true)
        }
        return if (a.validado == "no") Metodo(provisoria = true, pedirValidado = true) else Metodo()
    }

    /** Mañana, de 4 a 11.59 hora local. */
    fun momento(hora: Int): String = if (hora in 4..11) "manana" else "otro"

    /** Los pasos guiados de una sesión: cada uno con su espera y la toma que pide. */
    fun pasos(tipo: String, variante: String? = null): List<PasoGuiado> = when (tipo) {
        "ortostatica" -> listOf(
            PasoGuiado(300, if (variante == "sentado_parado") "sentado" else "acostado", null, null),
            PasoGuiado(60, "de_pie", 1, null),
            PasoGuiado(120, "de_pie", 3, null),
        )
        "comparacion_brazos" -> listOf("izq", "der", "der", "izq").mapIndexed { i, b -> PasoGuiado(if (i == 0) REPOSO_S else 60, "sentado", null, b) }
        else -> listOf(PasoGuiado(REPOSO_S, "sentado", null, null))
    }

    fun ortostatica(tomas: List<Toma>): Ortostatica? {
        val base = tomas.firstOrNull { it.posicion != "de_pie" } ?: return null
        val pie = tomas.filter { it.posicion == "de_pie" }
        if (pie.isEmpty()) return null
        val cs = pie.maxOf { base.sis - it.sis }
        val cd = pie.maxOf { base.dia - it.dia }
        val sp = pie.maxOf { it.pulso - base.pulso }
        val sube = pie.maxOf { it.sis - base.sis }
        return Ortostatica(cs, cd, sp, hipotension = cs >= 20 || cd >= 10, hipertensionPosible = sube >= 20 || pie.any { it.sis >= 140 && it.sis > base.sis })
    }

    private fun tiene(xs: List<String>, ys: List<String>) = xs.any { it in ys }

    /**
     * Una sesión: qué hace la app ahora (`paso` y `texto`), si la toma cuenta para el promedio y qué reglas se cumplen. La urgencia
     * y la alta se evalúan siempre, también en las tomas que no cuentan. Solo con tomas sentado.
     */
    fun evaluarSesion(s: Sesion): Evaluacion {
        val tipo = s.tipo.ifEmpty { "estandar" }
        val sint = s.sintomas
        // Orden estable, como el `sort` de JS: a igual `orden`, el que estaba antes.
        val sentadas = s.tomas.filter { it.sentado }.sortedBy { it.orden }
        val reglas = mutableListOf<String>()
        val niv = sentadas.map { nivelToma(it.sis, it.dia) }
        var conf180 = false
        var conf160 = false
        for (i in 1 until sentadas.size) {
            if (niv[i] == Nivel.URGENCIA && niv[i - 1] == Nivel.URGENCIA) conf180 = true
            if (niv[i] != Nivel.COMUN && niv[i - 1] != Nivel.COMUN) conf160 = true
        }
        // La comparación de brazos y la ortostática son secuencias fijas: no piden repetición.
        val guiada = tipo == "ortostatica" || tipo == "comparacion_brazos"
        val ultimo = niv.lastOrNull() ?: Nivel.COMUN
        val pendiente = !guiada && sentadas.isNotEmpty() && ((ultimo == Nivel.URGENCIA && !conf180) || (ultimo == Nivel.ALTA && !conf160))
        val min = s.minutosDesdeUltima

        var paso = Paso.LISTO
        var texto = "ninguno"
        val hayAlarma = deAlarma(sint)
        val pulso120 = sentadas.any { it.pulso >= 120 } && tiene(sint, listOf("palpitaciones", "dolor_pecho", "falta_aire", "mareo_al_pararse"))
        val pulso40 = sentadas.any { it.pulso <= 40 } && tiene(sint, listOf("mareo_al_pararse", "desmayo", "desmayo_en_esfuerzo"))
        if (hayAlarma) reglas += if (s.listaEspera == "si") "sintoma_alarma_en_espera" else "sintoma_alarma"
        if (tiene(sint, listOf("desmayo", "desmayo_en_esfuerzo"))) reglas += "desmayo"
        if (pulso120) reglas += "pulso_120_sintomas"
        if (pulso40) reglas += "pulso_40_mareo"
        if (conf180) reglas += "toma_180_120_confirmada" else if (conf160) reglas += "alta_toma_160_100"
        if (pendiente && ultimo == Nivel.URGENCIA && min >= SIN_REPETIR_MIN) reglas += "alta_180_120_sin_repetir"
        if (pendiente && ultimo == Nivel.ALTA && min >= RECORDATORIO_MIN) reglas += "repetir_pendiente"

        val urgSintomas = hayAlarma || pulso120 || pulso40
        if (urgSintomas) {
            paso = Paso.GUARDIA_SINTOMAS
            texto = "guardia_sintomas"
        } else if (conf180) {
            paso = Paso.GUARDIA_PRESION
            texto = "guardia_presion"
        } else if (pendiente) {
            paso = if (ultimo == Nivel.URGENCIA) Paso.REPETIR_CON_LISTA else Paso.REPETIR
            texto = if (min >= RECORDATORIO_MIN) "repetir_pendiente" else if (ultimo == Nivel.URGENCIA) "lista_sintomas_espera" else "quedate_sentado_5min"
        }

        val otrosMarcados = sint.filter { !deAlarma(listOf(it)) }
        if (sentadas.any { it.sis < 90 } && otrosMarcados.isNotEmpty()) {
            reglas += "sistolica_menor_90_sintomas"
            if (paso == Paso.LISTO) texto = "sentate_agua"
        }
        if ("mareo_al_pararse" in sint) {
            reglas += "sintomas_al_pararse"
            if (tipo == "ortostatica" && paso == Paso.LISTO) texto = "quedate_sentado_ortostatica"
        }
        if ("vomitos_diarrea" in sint) reglas += "sintoma_vomitos_diarrea"
        if (sentadas.any { it.pulso <= 40 } && sint.isEmpty()) reglas += "pulso_40_sin_sintomas"

        var orto: Ortostatica? = null
        if (tipo == "ortostatica") {
            orto = ortostatica(s.tomas)
            if (orto?.hipotension == true) reglas += "ortostatica_positiva"
        }

        val valor = if (sentadas.isEmpty()) null else Valor(media(sentadas.map { it.sis }), media(sentadas.map { it.dia }), media(sentadas.map { it.pulso }))
        val incumplida = s.previo.alguno || s.reposoCumplido != true || s.temporizadorSalteado == true
        var cuenta = false
        var motivo: String? = null
        when {
            s.tomas.isEmpty() -> motivo = "error"
            tipo == "bajo_efecto" -> motivo = "bajo_efecto"
            tipo == "ortostatica" -> motivo = "ortostatica"
            tipo == "comparacion_brazos" -> motivo = "comparacion_brazos"
            tipo == "suelta" -> motivo = "otra"
            sentadas.isEmpty() -> motivo = "error"
            incumplida -> motivo = "condicion_incumplida"
            pendiente -> motivo = "otra"
            else -> cuenta = true
        }
        if (motivo == "condicion_incumplida" && paso == Paso.LISTO && texto == "ninguno") texto = "toma_no_cuenta"
        val validaBajoEfecto = tipo == "bajo_efecto" && sentadas.isNotEmpty() && !pendiente && s.reposoCumplido == true && s.temporizadorSalteado != true &&
            s.entrenoEntreDosisYToma == false
        if (tipo == "bajo_efecto" && sentadas.isNotEmpty() && !validaBajoEfecto && paso == Paso.LISTO && texto == "ninguno") texto = "toma_no_cuenta"
        // Una toma suelta de 135/85 o más no avisa: dispara una serie de 3 tomas.
        if (tipo == "suelta" && valor != null && !pendiente && (valor.sis >= 135 || valor.dia >= 85)) reglas += "suelta_135_85"

        return Evaluacion(paso, texto, cuenta, motivo, valor, validaBajoEfecto, urgencia = urgSintomas || conf180, ortostatica = orto, reglas = reglas.sorted())
    }

    /** Para Mati y el servidor. NUNCA se le muestra al alumno. */
    fun categoria(sis: Int, dia: Int): String = when {
        sis >= 150 || dia >= 95 -> "hipertension_casa_estadio_2"
        sis >= 135 || dia >= 85 -> "hipertension_casa"
        sis >= 130 || dia >= 80 -> "limitrofe"
        sis >= 120 -> "elevada"
        else -> "optima"
    }

    private fun promedio(vs: List<Valor>): Valor? =
        if (vs.isEmpty()) null else Valor(media(vs.map { it.sis }), media(vs.map { it.dia }), media(vs.map { it.pulso }))

    /** La serie: 3 tomas válidas, una por día, en 3 días distintos dentro de los 7 días del inicio. */
    fun resumenSerie(e: EntradaSerie): ResumenSerie {
        val objetivo = e.tomasObjetivo?.takeIf { it != 0 } ?: 3
        val deBajoEfecto = e.tipo == "bajo_efecto"
        val inicio = e.fechaInicio?.takeIf { it.isNotEmpty() }
        val hasta = inicio?.let { DiaCalendario.numero(it) }?.let { DiaCalendario.texto(it + 6) }
        fun enPlazo(f: String): Boolean = if (inicio == null || hasta == null) true else f >= inicio && f <= hasta
        // `sortedWith` es estable: a igual fecha y orden, la que estaba antes.
        val ses = e.sesiones.sortedWith(compareBy<Sesion> { it.fecha ?: "" }.thenBy { it.orden ?: 0 })
        val reglas = mutableListOf<String>()
        val dias = mutableListOf<String>()
        val valores = mutableListOf<Valor>()
        val maxS = mutableListOf<Int>()
        val maxD = mutableListOf<Int>()
        val beDias = mutableListOf<String>()
        val beValores = mutableListOf<Valor>()
        var beN = 0
        var irregulares = 0
        for (s in ses) {
            val ev = evaluarSesion(s)
            reglas += ev.reglas
            irregulares += s.tomas.count { it.latidoIrregular }
            val fecha = s.fecha ?: ""
            val v = ev.valor
            if (s.tipo == "bajo_efecto") {
                beN++
                if (ev.validaBajoEfecto && v != null && enPlazo(fecha) && fecha !in beDias && beDias.size < objetivo) {
                    beDias += fecha
                    beValores += v
                }
            }
            if (ev.cuenta && v != null && enPlazo(fecha) && fecha !in dias && dias.size < objetivo) {
                dias += fecha
                valores += v
                for (x in s.tomas) {
                    maxS += x.sis
                    maxD += x.dia
                }
            }
        }
        val prom = promedio(valores)
        val validas = if (deBajoEfecto) beDias.size else dias.size
        val serieValida = validas >= objetivo

        if (!deBajoEfecto && serieValida && !e.soloUrgencias && prom != null && (prom.sis >= 135 || prom.dia >= 85)) reglas += "alta_promedio_135_85"
        if (valores.count { it.pulso >= 100 } >= 2) reglas += "pulso_100_dos_tomas"
        if (!deBajoEfecto && serieValida && e.basalPulso != null && prom != null && prom.pulso - e.basalPulso >= 20) reglas += "pulso_20_sobre_basal"
        if (irregulares >= 2) reglas += "latido_irregular_2_tomas"

        val bp = promedio(beValores)
        val beAlta = beValores.size >= 2 && ((bp?.sis ?: 0) >= 150 || (bp?.dia ?: 0) >= 95)
        val beAviso = beValores.size >= 2 && !beAlta && ((bp?.sis ?: 0) >= 135 || (bp?.dia ?: 0) >= 85)
        val bePulso = beValores.count { it.pulso >= 100 }
        if (beAlta) reglas += "alta_bajo_efecto_150_95"
        if (beAviso) reglas += "bajo_efecto_135_85"
        if (bePulso >= 2) reglas += "pulso_100_bajo_efecto"

        return ResumenSerie(
            tomasValidas = validas, dias = if (deBajoEfecto) beDias else dias, serieValida = serieValida, faltan = maxOf(0, objetivo - validas),
            promedio = prom, maximos = if (maxS.isEmpty()) null else maxS.max() to maxD.max(),
            categoria = if (!deBajoEfecto && serieValida && !e.soloUrgencias) prom?.let { categoria(it.sis, it.dia) } else null,
            bajoEfecto = BajoEfecto(beN, beValores.size, if (beValores.size >= 2) bp else null, bePulso, beAviso, beAlta),
            reglas = reglas.distinct().sorted(),
        )
    }
}
