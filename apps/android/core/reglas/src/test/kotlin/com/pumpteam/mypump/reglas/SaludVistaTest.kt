package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.RecuperacionDia
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import java.time.ZoneId
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test

private fun fila(fecha: String, tipo: String, valor: Double?, fuente: String = "apple_health", detalle: ValorJson? = null): FilaSalud {
    val o = linkedMapOf<String, ValorJson>(
        "fecha" to ValorJson.Texto(fecha), "tipo" to ValorJson.Texto(tipo), "valor" to (valor?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo),
        "fuente" to ValorJson.Texto(fuente),
    )
    if (detalle != null) o["detalle"] = detalle
    return FilaSalud.desde(ValorJson.Objeto(o).aJson())
}

private fun valorJson(e: JsonElement?): ValorJson? = if (e == null || e is JsonNull) null else ValorJson.desde(e)

/**
 * Gemelo de SaludVistaTests.swift: lo que muestran las cards, contra las funciones de cliente.html (salud_vista.json) y,
 * lo que vive adentro de un render, contra la web leída a mano.
 */
class SaludVistaTest {
    private val hoy = "2026-10-14"
    private val vector: JsonObject by lazy { Vectores.json(Vectores.publico("salud_vista"))["casos"]!!.jsonArray[0].jsonObject }

    @Test
    fun valorYSerieComoLaWeb() {
        val fallas = mutableListOf<String>()
        var total = 0
        for ((n, e) in vector["valores"]!!.jsonArray.withIndex()) {
            val esc = e.jsonObject
            val s = esc["salud"]!!.jsonArray.map(FilaSalud::desde)
            val fechas = esc["fechas"]!!.jsonArray.map { it.jsonPrimitive.content }
            for ((tipo, esperadoE) in esc["porTipo"]!!.jsonObject) {
                val esperado = esperadoE.jsonObject
                for ((f, v) in fechas.zip(esperado["valores"]!!.jsonArray)) {
                    total++
                    val web = if (v is JsonNull) null else v.jsonPrimitive.double
                    val kotlin = SaludVista.valor(s, tipo, f)
                    if (web != kotlin) fallas += "#$n valor $tipo $f: web $web, kotlin $kotlin"
                }
                total++
                val serie = SaludVista.serie(s, tipo)
                val web = esperado["serie"]!!.jsonArray.map { it.jsonObject }
                if (serie.map { it.fecha } != web.map { it["fecha"]!!.jsonPrimitive.content } ||
                    serie.map { it.valor } != web.map { it["valor"]!!.jsonPrimitive.double } ||
                    serie.map { it.detalle } != web.map { valorJson(it["detalle"]) }
                ) {
                    fallas += "#$n serie $tipo"
                }
            }
            val hoyEsc = esc["hoy"]!!.jsonPrimitive.content
            for (r in esc["recientes"]!!.jsonArray.map { it.jsonObject }) {
                total += 2
                val dias = r["dias"]!!.jsonPrimitive.int
                if (SaludVista.tieneReciente(s, listOf("fc_reposo", "hrv_ms", "sueno_min"), dias, hoyEsc) != r["nocturnos"]!!.jsonPrimitive.boolean) {
                    fallas += "#$n noche $dias"
                }
                if (SaludVista.tieneReciente(s, listOf("pasos", "actividad_min", "kcal_activas"), dias, hoyEsc) != r["diurnos"]!!.jsonPrimitive.boolean) {
                    fallas += "#$n día $dias"
                }
            }
        }
        assertTrue(total > 3000, "$total")
        assertTrue(fallas.isEmpty(), "${fallas.size} de $total: ${fallas.take(5)}")
    }

    @Test
    fun motivosComoLaWeb() {
        val motivos = vector["motivos"]!!.jsonArray
        val fallas = mutableListOf<String>()
        for ((n, c) in motivos.withIndex()) {
            val o = c.jsonObject
            val ms = SaludVista.motivos(RecuperacionDia(fecha = hoy, motivos = valorJson(o["motivos"])))
            val kotlin = ms.map { "${if (it.sube) "↑" else "↓"}|${it.antes}|${it.negrita}|${it.despues}" }
            val web = o["salida"]!!.jsonArray.map { s ->
                val x = s.jsonObject
                listOf("flecha", "antes", "negrita", "despues").joinToString("|") { x[it]!!.jsonPrimitive.content }
            }
            if (kotlin != web) fallas += "#$n: web $web, kotlin $kotlin"
        }
        assertTrue(motivos.size >= 100)
        assertTrue(fallas.isEmpty(), "${fallas.take(3)}")
    }

    @Test
    fun regularidadComoLaWeb() {
        for (c in vector["circular"]!!.jsonArray.map { it.jsonObject }) {
            val (m, sd) = SaludVista.promedioCircular(c["vals"]!!.jsonArray.map { it.jsonPrimitive.double })
            // Seno y coseno de V8 y de la JVM pueden diferir en el último bit: lo que se muestra tiene que ser igual.
            assertTrue(Math.abs(m - c["m"]!!.jsonPrimitive.double) < 1e-9 && Math.abs(sd - c["sd"]!!.jsonPrimitive.double) < 1e-9, "$c")
            assertEquals(c["dormirse"]!!.jsonPrimitive.content, SaludVista.horaReloj(m - 210))
            assertEquals(c["sdRedondo"]!!.jsonPrimitive.int.toLong(), jsEntero(sd))
        }
        for (r in vector["relojes"]!!.jsonArray.map { it.jsonObject }) {
            assertEquals(r["hhmm"]!!.jsonPrimitive.content, SaludVista.horaReloj(r["x"]!!.jsonPrimitive.double), "$r")
        }
    }

    // MARK: Card de Recuperación (renderMydayRecuperacion, a mano)

    private fun card(serie: List<RecuperacionDia>, conectado: Boolean = true, mostrar: Boolean = true, salud: List<FilaSalud> = emptyList(),
                     historial: Pair<Int, Int>? = null, sinDatos: Boolean = false) =
        SaludVista.cardRecuperacion(serie, conectado, mostrar, salud, historial, sinDatos, hoy)

    @Test
    fun sinScoreYSinConectarOfreceConectar() {
        assertEquals(SaludVista.CardRecuperacion.SinConectar, card(listOf(RecuperacionDia(hoy, estado = "insuficiente")), conectado = false))
        assertEquals(SaludVista.CardRecuperacion.SinConectar, card(emptyList(), conectado = false))
    }

    @Test
    fun conectadoSinScoreExplicaQueFalta() {
        val serie = listOf(RecuperacionDia(hoy, estado = "insuficiente"))
        fun caso(salud: List<FilaSalud>, historial: Pair<Int, Int>? = null, sinDatos: Boolean = false) =
            card(serie, salud = salud, historial = historial, sinDatos = sinDatos)
        assertEquals(SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.TrayendoHistorial(25, 60)), caso(emptyList(), 25 to 60))
        // Tuvo datos de la noche hace 10 días y ya no: va ANTES que "solo pasos" (tiene reloj, se le cortó).
        assertEquals(
            SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.FaltanDatosDeLaNoche),
            caso(listOf(fila("2026-10-04", "hrv_ms", 50.0), fila(hoy, "pasos", 8000.0))),
        )
        assertEquals(SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.SoloPasos), caso(listOf(fila("2026-10-12", "pasos", 8000.0))))
        assertEquals(SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.NoLlegaNada), caso(emptyList(), sinDatos = true))
        assertEquals(SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.Esperando), caso(emptyList()))
        // Un valor nulo no cuenta como dato.
        assertEquals(SaludVista.CardRecuperacion.ConectadoSinScore(SaludVista.SinScore.Esperando), caso(listOf(fila("2026-10-13", "pasos", null))))
    }

    @Test
    fun losTextosSonLosDeCadaTelefono() {
        val ios = TextosSalud.IOS
        // Los de iPhone, idénticos a los de iOS (SaludVista.swift).
        assertEquals("Este iPhone ya está mandando pasos y actividad. 👌", SaludVista.SinScore.SoloPasos.frase(ios))
        assertEquals("Conectado. Esperando los primeros datos de tu iPhone…", SaludVista.SinScore.Esperando.frase(ios))
        assertEquals("Fijate que el reloj esté sincronizando con la app Salud del iPhone.", SaludVista.SinScore.FaltanDatosDeLaNoche.nota(ios))
        assertEquals("Fijate que esté todo activado en Ajustes → Privacidad y seguridad → Salud → MyPump.", SaludVista.SinScore.NoLlegaNada.nota(ios))
        assertEquals(
            "Para el score de recuperación hace falta lo que se mide durmiendo — pulso en reposo, sueño y variabilidad — y eso lo da un reloj o " +
                "un anillo (Apple Watch, Oura, Garmin…). En cuanto uses uno, esto se arma solo.",
            SaludVista.SinScore.SoloPasos.nota(ios),
        )
        assertEquals("Trayendo tu historial de Salud… 25/60 días", SaludVista.SinScore.TrayendoHistorial(25, 60).frase())
        // En Android, los de `_TXT_SALUD.android`: nada de "iPhone" en un Samsung.
        assertEquals("Este teléfono ya está mandando pasos y actividad. 👌", SaludVista.SinScore.SoloPasos.frase())
        assertEquals("Conectado. Esperando los primeros datos de tu teléfono…", SaludVista.SinScore.Esperando.frase())
        assertEquals("Fijate que el reloj esté sincronizando con Health Connect.", SaludVista.SinScore.FaltanDatosDeLaNoche.nota())
        assertEquals("Fijate que esté todo activado en Ajustes → Salud y bienestar → Health Connect → MyPump.", SaludVista.SinScore.NoLlegaNada.nota())
        assertTrue(SaludVista.SinScore.SoloPasos.nota().contains("(Galaxy Watch, Mi Band, Garmin, Fitbit…)"))
        for (s in listOf(SaludVista.SinScore.TrayendoHistorial(1, 2), SaludVista.SinScore.FaltanDatosDeLaNoche, SaludVista.SinScore.SoloPasos,
            SaludVista.SinScore.NoLlegaNada, SaludVista.SinScore.Esperando)) {
            assertFalse((s.frase() + s.nota()).contains("iPhone"), "$s")
        }
    }

    /** Cada texto de las dos plataformas está escrito igual en `_TXT_SALUD` de cliente.html. */
    @Test
    fun losTextosSalenDeLaWeb() {
        val html = Files.readString(Vectores.raizRepo.resolve("public/cliente.html"))
        for (t in listOf(TextosSalud.IOS, TextosSalud.ANDROID)) {
            for (v in listOf(t.app, t.boton, t.dispositivo, t.telefono, t.esteTel, t.sinApp, t.relojes, t.sincroniza, t.desdeApp, t.revocar)) {
                assertTrue(html.contains("'$v'"), "no está en cliente.html: $v")
            }
        }
    }

    @Test
    fun calibrandoMuestraLoQueYaSabe() {
        val c1 = card(listOf(RecuperacionDia(hoy, estado = "calibrando", diasDatos = 5, cobertura = ValorJson.objeto("sueno_min" to ValorJson.Numero(452.0)))))
        assertEquals(SaludVista.CardRecuperacion.Calibrando(5, 36, "Ya sé que dormís cerca de 7h32."), c1)
        val c2 = card(listOf(RecuperacionDia(hoy, estado = "calibrando", diasDatos = 20, cobertura = ValorJson.objeto("fc_reposo" to ValorJson.Numero(51.5)))))
        assertEquals(SaludVista.CardRecuperacion.Calibrando(20, 100, "Ya sé que tu pulso en reposo ronda los 52."), c2)
        // Un día de datos gigante no rompe el porcentaje (`Int(jsRound(Double(n) / 14 * 100))` cerraba la app en iOS).
        val c3 = card(listOf(RecuperacionDia(hoy, estado = "calibrando", diasDatos = Int.MAX_VALUE)))
        assertEquals(SaludVista.CardRecuperacion.Calibrando(Int.MAX_VALUE, 100, ""), c3)
    }

    @Test
    fun conScoreFraseMotivosYScoreViejo() {
        val motivos = ValorJson.Lista(
            listOf(ValorJson.objeto("tipo" to ValorJson.Texto("sueno"), "dir" to ValorJson.Numero(-1.0), "valor" to ValorJson.Numero(372.0), "baseline" to ValorJson.Numero(455.0))),
        )
        val serie = (1..11).map { RecuperacionDia("2026-10-0${minOf(it, 9)}", score = 60 + it, estado = "ok", banda = "media") }.toMutableList()
        serie += RecuperacionDia("2026-10-12", score = 81, estado = "ok", banda = "alta", motivos = motivos)
        serie += RecuperacionDia("2026-10-13", estado = "insuficiente")
        serie += RecuperacionDia(hoy, estado = "insuficiente")
        val c = (card(serie) as? SaludVista.CardRecuperacion.ConScore)?.score ?: fail("esperaba score")
        assertTrue(c.fila.score == 81 && c.banda == "alta" && c.bandaTexto == "Recuperado")
        assertEquals(listOf("Dormiste 6h12 · venís de 7h35"), c.motivos.map { it.texto })
        assertNull(c.frase)   // con motivos no hay frase genérica
        assertEquals("Score de lunes: la de anoche todavía no llegó.", c.notaVieja)
        assertEquals(12, c.grafico.size)
        // Apagado por el cliente: no hay número.
        assertEquals(SaludVista.CardRecuperacion.Oculto, card(serie, mostrar = false))
        // Sin motivos, la frase sale de la banda; discordancia y estado autonómico ganan.
        val b = (card(listOf(RecuperacionDia(hoy, score = 30, estado = "ok", banda = "baja"))) as SaludVista.CardRecuperacion.ConScore).score
        assertTrue(b.frase == "Hoy tu cuerpo pide más descanso." && b.notaVieja == null && b.grafico.isEmpty())
        val fat = listOf(RecuperacionDia(hoy, score = 40, estado = "ok", banda = "baja", estadoAutonomico = "fatiga_acumulada", discordancia = true))
        assertEquals("Los números dicen una cosa y vos me dijiste otra. Le creo a lo que sentís.", (card(fat) as SaludVista.CardRecuperacion.ConScore).score.frase)
    }

    /** Lo que la web hace con valores raros de un motivo (la aritmética de JS), leído con node sobre `_recDrivers`. */
    @Test
    fun motivosConValoresRarosComoJs() {
        fun motivo(vararg campos: Pair<String, ValorJson>): List<String> =
            SaludVista.motivos(RecuperacionDia(hoy, motivos = ValorJson.Lista(listOf(ValorJson.objeto(*campos))))).map { it.texto }
        val sueno = "tipo" to ValorJson.Texto("sueno")
        assertEquals(listOf("Dormiste 0h00"), motivo(sueno, "valor" to ValorJson.Nulo))          // null es 0 (iOS: "NaNhNaN")
        assertEquals(listOf("Dormiste NaNhNaN"), motivo(sueno))                                    // ausente es NaN
        assertEquals(listOf("Dormiste 7h32 · venís de 0h00"), motivo(sueno, "valor" to ValorJson.Numero(452.0), "baseline" to ValorJson.Texto("0")))
        val carga = "tipo" to ValorJson.Texto("carga")
        assertEquals(listOf("Entrenaste fuerte: 9 series duras en 3 días"), motivo(carga, "agudo" to ValorJson.Texto("9")))
        assertEquals(listOf("Entrenaste fuerte: undefined series duras en 3 días"), motivo(carga))
        assertEquals(listOf("Entrenaste fuerte: 1000000000000000 series duras en 3 días"), motivo(carga, "agudo" to ValorJson.Numero(1e15)))
        assertEquals(listOf("Entrenaste fuerte: 1e-7 series duras en 3 días"), motivo(carga, "agudo" to ValorJson.Numero(1e-7)))
        val fc = "tipo" to ValorJson.Texto("fc_reposo")
        assertEquals(listOf("Pulso en reposo 60"), motivo(fc, "valor" to ValorJson.Numero(60.0), "baseline" to ValorJson.Numero(60.2)))
        assertEquals(listOf("Pulso en reposo 61 · 1 más que tu normal"), motivo(fc, "valor" to ValorJson.Numero(61.0), "baseline" to ValorJson.Numero(60.0)))
        // Un elemento que no es objeto se saltea (la web tiraba un TypeError con un null).
        assertTrue(SaludVista.motivos(RecuperacionDia(hoy, motivos = ValorJson.Lista(listOf(ValorJson.Nulo, ValorJson.Numero(3.0))))).isEmpty())
        assertTrue(SaludVista.motivos(RecuperacionDia(hoy, motivos = ValorJson.objeto())).isEmpty())
    }

    // MARK: Card Salud y Mis datos

    @Test
    fun resumenDeLaCardSalud() {
        val salud = listOf(
            fila(hoy, "pasos", 8548.161), fila(hoy, "pasos", 9000.0, "manual"), fila("2026-10-13", "pasos", 6000.0),
            fila("2026-10-13", "sueno_min", 452.0, "oura"), fila("2026-10-13", "sueno_min", 430.0),
            fila("2026-10-13", "hrv_ms", 40.0, detalle = ValorJson.objeto("metrica" to ValorJson.Texto("sdnn"))),
            fila("2026-10-13", "hrv_ms", 55.0, "whoop", ValorJson.objeto("metrica" to ValorJson.Texto("rmssd"))),
            fila(hoy, "actividad_min", 32.0),
        )
        val r = SaludVista.resumen(salud, hoy)!!
        assertEquals(8548.161, r.pasosHoy)          // apple_health le gana a lo manual
        assertEquals(452.0, r.suenoAnoche)          // no hay de hoy: el de ayer, y Oura gana
        assertEquals(55.0, r.hrv)                   // el rMSSD gana
        assertEquals(32.0, r.minutosActivosHoy)
        assertTrue(r.diasPromedio == 2 && r.promedioPasos == 7274L)
        assertNull(SaludVista.resumen(listOf(fila(hoy, "sueno_min", 400.0)), hoy))
        assertTrue(SaludVista.miles(8548.161) == "8.548" && SaludVista.miles(1234567.0) == "1.234.567" && SaludVista.miles(999.0) == "999")
        assertTrue(SaludVista.horas(452.0) == "7h 32" && SaludVista.horasSinEspacio(59.6) == "0h60")
    }

    @Test
    fun componentesSeRepartenEntreLosPresentes() {
        val comp = ValorJson.objeto(
            "autonomico" to ValorJson.objeto("score" to ValorJson.Numero(72.4), "peso" to ValorJson.Numero(45.0)),
            "sueno" to ValorJson.objeto("score" to ValorJson.Numero(50.0), "peso" to ValorJson.Numero(25.0)),
            "carga" to ValorJson.objeto("score" to ValorJson.Nulo, "peso" to ValorJson.Numero(20.0)),
        )
        val c = SaludVista.componentes(RecuperacionDia(hoy, score = 66, componentes = comp))
        assertEquals(listOf("autonomico", "sueno"), c.map { it.clave })
        assertEquals(listOf(72L, 50L), c.map { it.score })
        assertEquals(listOf(64L, 36L), c.map { it.aporte })
        assertTrue(SaludVista.componentes(RecuperacionDia(hoy, estado = "calibrando", componentes = comp)).isEmpty())
        // Pesos que suman 0: se reparte sobre 1 (`|| 1`), como la web.
        val sinPeso = ValorJson.objeto("sueno" to ValorJson.objeto("score" to ValorJson.Numero(50.0)))
        assertEquals(listOf(0L), SaludVista.componentes(RecuperacionDia(hoy, score = 50, componentes = sinPeso)).map { it.aporte })
    }

    @Test
    fun filaDeMetricaConPromediosYFlecha() {
        val salud = (1..9).map { fila("2026-10-0$it", "fc_reposo", 50.0) } + fila("2026-10-10", "fc_reposo", 56.0)
        val f = SaludVista.fila(salud, "fc_reposo", mejorSube = false)!!
        assertEquals("56", f.valor)
        assertTrue(f.delta == "↑ 5" && !f.deltaEsBueno)   // promedio 50,6: subir el pulso no es bueno
        assertTrue(f.promedio7 == "51" && f.promedio30 == "51" && f.diasConDato == 10)
        assertNull(SaludVista.fila(salud, "pasos"))
        assertEquals("Anoche", SaludVista.rotuloNoche(hoy, hoy))
        assertEquals("Anteanoche", SaludVista.rotuloNoche("2026-10-13", hoy))
        assertEquals("Noche del 12 sept", SaludVista.rotuloNoche("2026-09-12", hoy))
        assertEquals("56.0", SaludVista.unDecimal(56.0))
        val r = SaludVista.regularidad((1..5).map { fila("2026-10-0$it", "sueno_medio_min", 180.0 + it) })!!
        assertEquals("23:33", r.horaDormirse)
        assertEquals("Muy regular — eso ayuda tanto como dormir más.", r.texto)
        assertNull(SaludVista.regularidad((1..3).map { fila("2026-10-0$it", "sueno_medio_min", 180.0) }))
    }

    // MARK: Fechas locales como JS

    @Test
    fun medianochesYMediodiaComoJs() {
        // Nueva York, la semana del cambio de hora (1-nov-2026): 7 días atrás desde el 4-nov a las 8:45.
        val ny = RelojLocal(ZoneId.of("America/New_York"))
        val ahora = 1_793_799_917_345.0   // 2026-11-04T08:45:17.345-05:00
        assertEquals("2026-10-28T04:00:00.000Z", RelojLocal.iso(ny.medianoche(7, ahora)))   // todavía EDT
        assertEquals("2026-11-04T05:00:00.000Z", RelojLocal.iso(ny.medianoche(0, ahora)))
        assertEquals("2026-10-27T16:00:00.000Z", RelojLocal.iso(ny.mediodiaDelDiaAnterior(ny.medianoche(7, ahora))))
        assertEquals("2026-11-04", ny.ymd(ahora))
        assertEquals("2026-10-15T02:50:17.345Z", RelojLocal.iso(1_792_032_617_345.0))
        assertEquals(1_791_986_340_123.0, RelojLocal.desdeIso("2026-10-14 13:59:00.123456+00:00"))
        assertEquals(1_791_986_340_000.0, RelojLocal.desdeIso("2026-10-14T13:59:00Z"))
        assertNull(RelojLocal.desdeIso("ayer"))
        // Un día 0 es el último del mes anterior, como `new Date(y, m, 0)`; y un NaN no tira.
        assertEquals("1970-01-01T00:00:00.000Z", RelojLocal.iso(Double.NaN))
        val utc = RelojLocal(ZoneId.of("UTC"))
        assertEquals("2026-10-31", utc.ymd(utc.medianoche(3, 1_793_707_200_000.0)))   // el 3-nov − 3 días
    }

    // MARK: Lo que se muestra con números raros (NumerosAbsurdosTests.swift)

    @Test
    fun formatosConNumerosRaros() {
        assertEquals("1e+21", SaludVista.enteroJS(1e21))
        assertEquals("57", SaludVista.enteroJS(57.4))
        assertEquals("0", SaludVista.enteroJS(-0.3))
        assertEquals("NaN", SaludVista.enteroJS(Double.NaN))
        assertEquals("100.000.000.000.000.000.000", SaludVista.miles(1e20))
        assertEquals("8.548", SaludVista.miles(8548.2))
        assertEquals("-1.234", SaludVista.miles(-1234.0))
        assertEquals(SaludVista.horaReloj(1e300 % 1440), SaludVista.horaReloj(1e300))
        assertEquals("22:30", SaludVista.horaReloj(-90.0))
        assertEquals("NaN:NaN", SaludVista.horaReloj(Double.POSITIVE_INFINITY))
        assertEquals("7h 05", SaludVista.horas(425.0))
        SaludVista.horas(1e300)
        // Lo que da `toLocaleString('es-AR')` de ICU (node 26): los dígitos más cortos, "-0" e "∞".
        assertEquals("100.000.000.000.000.000.000.000", SaludVista.miles(1e23))
        assertEquals("1.000.000.000.000.000.000.000", SaludVista.miles(1e21))
        assertEquals("123.456.789.012.345.680.000", SaludVista.miles(123456789012345680000.0))
        assertEquals("9.007.199.254.740.992", SaludVista.miles(9007199254740993.0))
        assertEquals("-0", SaludVista.miles(-0.3))
        assertEquals("∞", SaludVista.miles(Double.POSITIVE_INFINITY))
        assertEquals("NaN", SaludVista.miles(Double.NaN))
    }

    // MARK: Las tablas del bridge por plataforma

    @Test
    fun lasTablasDeCadaPlataforma() {
        val ios = PuenteSalud.tiposLectura(PlataformaSalud.IOS, 18)
        assertEquals(
            listOf("steps", "calories", "restingHeartRate", "exerciseTime", "respiratoryRate", "oxygenSaturation", "appleSleepingWristTemperature",
                "bodyFat", "weight", "distance", "flightsClimbed", "basalCalories", "bodyTemperature", "bloodGlucose", "mindfulness", "heartRate",
                "sleep", "heartRateVariability", "workouts"),
            ios,
        )
        assertFalse(PuenteSalud.tiposLectura(PlataformaSalud.IOS, 15).contains("appleSleepingWristTemperature"))
        assertTrue(PuenteSalud.tiposLectura(PlataformaSalud.IOS, 0).contains("appleSleepingWristTemperature"))
        // Android: sin los soloIOS (ni la saturación, que Google rechazó) y sin mirar la versión de iOS.
        assertEquals(
            listOf("steps", "calories", "restingHeartRate", "respiratoryRate", "bodyFat", "weight", "distance", "flightsClimbed", "basalCalories",
                "heartRate", "sleep", "heartRateVariability", "workouts"),
            PuenteSalud.tiposLectura(PlataformaSalud.ANDROID, 0),
        )
        assertEquals(listOf("respiratoryRate", "bodyFat", "distance", "flightsClimbed", "basalCalories", "heartRate", "workouts"),
            PuenteSalud.resto(PlataformaSalud.ANDROID, 0))
        // basalCalories es una tasa en Health Connect: la mediana, no la suma.
        val basal = PuenteSalud.muestras.first { it.dataType == "basalCalories" }
        val reloj = RelojLocal(ZoneId.of("UTC"))
        val ms = (0..3).map { MuestraSalud(1_791_000_000_000.0 + it * 3_600_000, 1_791_000_000_000.0 + it * 3_600_000, 1800.0, "hc", "Health Connect") }
        assertEquals(listOf(7200.0), AgregacionSalud.muestras(ms, basal, reloj, PlataformaSalud.IOS).map { it.valor })
        val android = AgregacionSalud.muestras(ms, basal, reloj, PlataformaSalud.ANDROID)
        assertEquals(listOf(1800.0), android.map { it.valor })
        assertEquals("health_connect", android.single().fuente)
    }

    /** Las mitades de una ventana partida se pegan con la clave de texto de la web (`${s.value}`): 0 y −0 son lo mismo, y
     *  dos NaN también; otra fuente es otra muestra. */
    @Test
    fun lasMitadesSePeganComoLaWeb() {
        fun m(valor: Double, fuente: String = "a") = MuestraSalud(1.0, 2.0, valor, fuente, "A")
        assertEquals(1, AgregacionSalud.sinRepetidas(listOf(m(Double.NaN)), listOf(m(Double.NaN))).size)
        assertEquals(1, AgregacionSalud.sinRepetidas(listOf(m(0.0)), listOf(m(-0.0))).size)
        assertEquals(2, AgregacionSalud.sinRepetidas(listOf(m(5.0)), listOf(m(5.0, "b"))).size)
        assertEquals(listOf(5.0, 6.0), AgregacionSalud.sinRepetidas(listOf(m(5.0), m(5.0)), listOf(m(6.0), m(5.0))).map { it.valor })
    }

    /** Una sesión de Health Connect con sus etapas: una etapa por evento y un 'inbed' del largo de la sesión. */
    @Test
    fun unaSesionConEtapas() {
        val reloj = RelojLocal(ZoneId.of("America/Argentina/Buenos_Aires"))
        val ini = 1_791_943_200_000.0   // 2026-10-13 23:00 en Buenos Aires
        val min = 60_000.0
        val sesion = MuestraSalud(
            ini, ini + 480 * min, 480.0, "com.sec.android.app.shealth", "Samsung Health",
            etapas = listOf(
                EtapaSueno(ini, ini + 100 * min, "light"), EtapaSueno(ini + 100 * min, ini + 190 * min, "deep"),
                EtapaSueno(ini + 190 * min, ini + 220 * min, "awake"), EtapaSueno(ini + 220 * min, ini + 480 * min, "rem"),
            ),
        )
        val s = AgregacionSalud.procesarSueno(listOf(sesion), reloj, PlataformaSalud.ANDROID)
        val porTipo = s.filas.associate { it.tipo to it.valor }
        assertEquals(450.0, porTipo["sueno_min"])                  // 480 − 30 despierto
        assertEquals(94.0, porTipo["sueno_eficiencia_pct"])        // 450 / 480
        assertEquals(100.0, porTipo["sueno_ligero_min"])
        assertEquals(90.0, porTipo["sueno_profundo_min"])
        assertEquals(260.0, porTipo["sueno_rem_min"])
        assertEquals(180.0, porTipo["sueno_medio_min"])            // 03:00
        assertEquals("2026-10-14", s.noches.single().fecha)
        assertTrue(s.filas.all { it.fuente == "health_connect" })
    }
}
