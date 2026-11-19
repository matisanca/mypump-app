package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.FotoProgreso
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private val ar = ZoneId.of("America/Argentina/Buenos_Aires")

private fun reg(fecha: String, kg: Double?): RegistroHistorico = RegistroHistorico.desde(
    ValorJson.objeto(
        "registrado_en" to ValorJson.Texto(fecha), "clave" to ValorJson.Texto("x"),
        "peso_kg" to (kg?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo),
    ).aJson(),
)

/** Gemelo de ProgresoTests.swift: el resumen por ejercicio de la web. */
class ProgresoTest {
    @Test
    fun maximoPorSesionUltimasOchoYVariacion() {
        // 10 sesiones (de la más nueva a la más vieja, como llegan), dos series por sesión.
        val filas = (10 downTo 1).flatMap { d ->
            listOf(reg("2026-09-%02dT14:00:00+00:00".format(d), 50.0 + d), reg("2026-09-%02dT14:05:00+00:00".format(d), 45.0 + d))
        }
        val r = ProgresoEjercicio.resumen(filas, ar)!!
        assertEquals(listOf(53.0, 54.0, 55.0, 56.0, 57.0, 58.0, 59.0, 60.0), r.serie)
        assertEquals(60.0, r.tope)
        assertEquals(13.2, r.variacion)          // (60-53)/53 = 13,207…
        assertTrue(r.esPR)
        assertEquals(10, ProgresoEjercicio.sesiones(filas, ar).size)
    }

    @Test
    fun sinPRSiLaUltimaNoSuperaYUnaSolaSesion() {
        val r = ProgresoEjercicio.resumen(listOf(reg("2026-09-02T14:00:00+00:00", 60.0), reg("2026-09-01T14:00:00+00:00", 60.0)), ar)!!
        assertFalse(r.esPR)
        assertEquals(0.0, r.variacion)
        val una = ProgresoEjercicio.resumen(listOf(reg("2026-09-01T14:00:00+00:00", 60.0)), ar)!!
        assertTrue(una.variacion == null && !una.esPR)
        assertNull(ProgresoEjercicio.resumen(emptyList(), ar))
    }

    /** Lo esperado de `fechaLocalDe` corrido en node con TZ=America/Argentina/Buenos_Aires. */
    @Test
    fun laFechaEsLaLocal() {
        // 01:30 UTC del 2/9 es el 1/9 en Buenos Aires.
        assertEquals("2026-09-01", FechaLocal.de("2026-09-02T01:30:00.123456+00:00", ar))
        assertEquals("2026-09-01", FechaLocal.de("2026-09-02 01:30:00+00", ar))   // el texto de Postgres
        assertEquals("2026-09-01", FechaLocal.de("2026-09-02T01:30:00Z", ar))
        assertEquals("basura", FechaLocal.de("basura", ar))
        assertEquals("", FechaLocal.de("T2026", ar))                              // String(iso).split('T')[0]
        assertEquals("", FechaLocal.de("", ar))
    }

    @Test
    fun pesoNuloCuentaComoCero() {
        val r = ProgresoEjercicio.resumen(listOf(reg("2026-09-02T14:00:00+00:00", 40.0), reg("2026-09-01T14:00:00+00:00", null)), ar)!!
        assertEquals(listOf(0.0, 40.0), r.serie)
        assertNull(r.variacion)                  // arranca en 0
        assertTrue(r.esPR)
    }

    /** `toFixed(1)` de JS (lo esperado salió de node): el empate se decide con el valor exacto del double. */
    @Test
    fun toFixedComoJs() {
        val casos = listOf(0.15 to "0.1", 0.25 to "0.3", 0.35 to "0.3", 1.25 to "1.3", -1.25 to "-1.3", -0.04 to "-0.0",
            -0.0 to "0.0", 13.2075 to "13.2", 1.05 to "1.1", 2.675 to "2.7", 81.95 to "82.0", 82.35 to "82.3", 0.05 to "0.1",
            1e21 to "1e+21", 123.45 to "123.5", -123.45 to "-123.5", 9.95 to "9.9", 0.95 to "0.9")
        for ((x, js) in casos) assertEquals(js, toFixed(x, 1), "($x).toFixed(1)")
    }
}

private fun salud(vararg filas: Triple<String, Double?, String>): List<FilaSalud> = filas.map { (fecha, valor, fuente) ->
    FilaSalud.desde(
        ValorJson.objeto("fecha" to ValorJson.Texto(fecha), "tipo" to ValorJson.Texto("peso_kg"),
            "valor" to (valor?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo), "fuente" to ValorJson.Texto(fuente)).aJson(),
    )
}

/** Gemelo de RevisionTests.swift: peso y check, como la web. */
class RevisionTest {
    @Test
    fun laSerieDaPrioridadALoManualYDescartaCeros() {
        val s = PesoCorporal.serie(salud(Triple("2026-10-12", 82.4, "apple_health"), Triple("2026-10-12", 82.0, "manual"),
            Triple("2026-10-10", 82.1, "manual"), Triple("2026-10-11", 0.0, "manual"), Triple("2026-10-09", null, "manual")))
        assertEquals(listOf(PesoCorporal.Punto("2026-10-10", 82.1), PesoCorporal.Punto("2026-10-12", 82.0)), s)
    }

    @Test
    fun mediaDeSieteDiasYDeltaSemanal() {
        // Semana anterior (01-07): 80 kg; esta (08-14): 80,5 kg → +500 g.
        val filas = (1..7).map { Triple("2026-10-%02d".format(it), 80.0 as Double?, "manual") } +
            (8..14).map { Triple("2026-10-%02d".format(it), 80.5 as Double?, "manual") }
        val s = PesoCorporal.serie(salud(*filas.toTypedArray()))
        assertEquals(80.5, PesoCorporal.media(s, "2026-10-14", 7))
        assertEquals(80.0, PesoCorporal.media(s, "2026-10-07", 7))
        // (fin − 7, fin]: el 7 no entra en la semana que termina el 14.
        assertEquals(80.5, PesoCorporal.media(s, "2026-10-08", 1))
        assertEquals(500, PesoCorporal.deltaSemanal(s, "2026-10-14"))
        assertEquals("+500 g", PesoCorporal.textoDelta(500))
        assertEquals("-1,3 kg", PesoCorporal.textoDelta(-1250))
        assertEquals("+1,0 kg", PesoCorporal.textoDelta(1000))
        assertNull(PesoCorporal.deltaSemanal(s.takeLast(3), "2026-10-14"))
        assertEquals(s.size, PesoCorporal.lineaMedia(s).size)
    }

    @Test
    fun leerElPeso() {
        assertEquals(82.4, PesoCorporal.leer("82,35"))
        assertEquals(30.0, PesoCorporal.leer(" 30 "))
        assertNull(PesoCorporal.leer("29,9"))
        assertNull(PesoCorporal.leer("300,1"))
        assertNull(PesoCorporal.leer("abc"))
        assertEquals("82,0", PesoCorporal.kg(81.95))
    }

    @Test
    fun checkFaltan() {
        assertNull(CheckinSemanal.faltan(mapOf("energia" to 3, "descanso" to 4, "hambre" to 2, "adherencia" to 5)))
        assertEquals("Faltan: Descanso, Hambre, Adherencia", CheckinSemanal.faltan(mapOf("energia" to 3, "hambre" to 0)))
    }

    @Test
    fun racha() = assertEquals(listOf("💤", "✨", "✨", "⚡", "⚡", "🔥", "🔥"), listOf(0, 1, 2, 3, 6, 7, 30).map(RachaTexto::icono))

    @Test
    fun dias() {
        assertEquals("2026-10-14", DiaCalendario.numero("2026-10-14")?.let(DiaCalendario::texto))
        assertEquals(1L, DiaCalendario.numero("2026-03-01")!! - DiaCalendario.numero("2026-02-28")!!)
        assertNull(DiaCalendario.numero("x"))
        // Como `new Date("…T00:00:00")` de la web (node): un día de más pasa al mes siguiente; el mes 13 no existe.
        assertEquals("2026-03-02", DiaCalendario.numero("2026-02-30")?.let(DiaCalendario::texto))
        assertNull(DiaCalendario.numero("2026-13-01"))
    }
}

private fun foto(semana: String, pose: String) = FotoProgreso.desde(
    ValorJson.objeto("semana_lunes" to ValorJson.Texto(semana), "pose" to ValorJson.Texto(pose)).aJson(),
)

/** Gemelo de FotosProgresoTests (RevisionTests.swift): semanas, racha y comparador como la web. */
class FotosProgresoTest {
    @Test
    fun lunesIso() {
        assertEquals("2026-10-12", FotosProgreso.lunes("2026-10-14"))   // miércoles
        assertEquals("2026-10-12", FotosProgreso.lunes("2026-10-12"))   // lunes
        assertEquals("2026-10-12", FotosProgreso.lunes("2026-10-18"))   // domingo
        assertEquals("2026-02-23", FotosProgreso.lunes("2026-03-01"))
        assertEquals("1969-12-29", FotosProgreso.lunes("1970-01-01"))   // antes de la época: el módulo no se vuelve negativo
    }

    @Test
    fun rachaDeSemanasCompletasHaciaAtras() {
        val f = listOf("2026-09-14", "2026-09-28", "2026-10-05").flatMap { s -> listOf("frente", "perfil", "espalda").map { foto(s, it) } } +
            foto("2026-10-12", "frente")             // la actual, incompleta, no corta la racha
        assertEquals(2, FotosProgreso.racha(f))     // 28/9 y 5/10; el 21/9 falta
        assertEquals(listOf("2026-09-14", "2026-09-28", "2026-10-05", "2026-10-12"), FotosProgreso.semanas(f))
        assertEquals(0, FotosProgreso.racha(emptyList()))
    }

    @Test
    fun posesDeLaSemanaConPendientes() {
        val s = FotosProgreso.posesDeLaSemana(listOf(foto("2026-10-12", "frente")),
            listOf("perfil" to "2026-10-14", "espalda" to "2026-10-05"), "2026-10-12")
        assertEquals(setOf("frente", "perfil"), s)
        val p = FotosProgreso.pendientes(checkinEnviado = true, posesDeLaSemana = s)
        assertTrue(p.total == 1 && p.faltanFotos && !p.faltaCheck)
        assertEquals("Te faltan tu check y tus fotos de la semana", FotosProgreso.textoRecordatorio(faltaCheck = true, faltanFotos = true))
    }

    @Test
    fun resumenDelComparador() {
        val peso = listOf(PesoCorporal.Punto("2026-09-15", 84.0), PesoCorporal.Punto("2026-10-13", 81.6))
        assertEquals("4 semanas · -2,4 kg", FotosProgreso.resumenComparador("2026-09-14", "2026-10-12", peso))
        assertEquals("1 semana", FotosProgreso.resumenComparador("2026-10-05", "2026-10-12", emptyList()))
    }

    /** El peso del comparador (2.3.3): el de la semana de cada foto, o el más cercano en ±7 días; sin kg si no se puede decir. */
    @Test
    fun pesoDelComparador() {
        fun p(vararg l: Pair<String, Double>) = l.map { PesoCorporal.Punto(it.first, it.second) }
        fun r(a: String, b: String, vararg l: Pair<String, Double>) = FotosProgreso.resumenComparador(a, b, p(*l))
        // Emmanuel: con la regla vieja (el primero desde el lunes, sobre 60 días) veía +0,7.
        assertEquals("11 semanas · -4,6 kg",
            r("2026-08-31", "2026-11-16", "2026-09-02" to 73.0, "2026-09-20" to 72.1, "2026-11-16" to 68.4, "2026-11-18" to 68.9))
        // La semana sin peso toma el más cercano: 3 días antes del lunes le gana a 5 después del domingo.
        assertEquals("8 semanas · -2,4 kg", r("2026-09-14", "2026-11-09", "2026-09-11" to 82.0, "2026-09-25" to 81.0, "2026-11-10" to 79.6))
        // Empate (4 y 4): el de después.
        assertEquals("8 semanas · -1,4 kg", r("2026-09-14", "2026-11-09", "2026-09-10" to 82.0, "2026-09-24" to 81.0, "2026-11-10" to 79.6))
        // A 7 días justos entra; a 8, no.
        assertEquals("8 semanas · -2,4 kg", r("2026-09-14", "2026-11-09", "2026-09-07" to 82.0, "2026-11-10" to 79.6))
        assertEquals("8 semanas", r("2026-09-14", "2026-11-09", "2026-09-06" to 82.0, "2026-09-28" to 81.0, "2026-11-10" to 79.6))
        // Libras contra kilos: pasa el 25 %. El 25 % justo se muestra.
        assertEquals("12 semanas", r("2026-08-17", "2026-11-09", "2026-08-17" to 219.0, "2026-11-10" to 101.4))
        assertEquals("8 semanas · -20,0 kg", r("2026-09-14", "2026-11-09", "2026-09-14" to 80.0, "2026-11-09" to 60.0))
        // El mismo pesaje en las dos fotos (la regla vieja decía «1 semana · 0,0 kg»).
        assertEquals("1 semana", r("2026-11-02", "2026-11-09", "2026-11-09" to 80.0))
        // La última toma un pesaje de la semana de la primera (es el cambio dentro de la semana 1).
        assertEquals("1 semana", r("2026-11-02", "2026-11-09", "2026-11-02" to 80.0, "2026-11-08" to 79.4))
        // Un 0,0 real (dos pesajes, cada uno en su semana) se muestra, sin signo.
        assertEquals("1 semana · 0,0 kg", r("2026-11-02", "2026-11-09", "2026-11-02" to 80.0, "2026-11-10" to 80.0))
        assertEquals("1 semana · 0,0 kg", r("2026-11-02", "2026-11-09", "2026-11-02" to 80.0, "2026-11-10" to 80.04))
        assertEquals("1 semana · 0,0 kg", r("2026-11-02", "2026-11-09", "2026-11-02" to 80.0, "2026-11-10" to 79.96))
        assertEquals("1 semana · +0,5 kg", r("2026-11-02", "2026-11-09", "2026-11-02" to 80.0, "2026-11-10" to 80.5))
        assertEquals(82.0, FotosProgreso.pesoDeSemana("2026-09-14", p("2026-09-16" to 81.0, "2026-09-15" to 82.0)))
        assertNull(FotosProgreso.pesoDeSemana("mal", p("2026-09-15" to 82.0)))
    }

    /** Desde cuándo se pide el peso del comparador: el lunes de la foto más vieja menos 7 días; solo si Salud no llega. */
    @Test
    fun desdeDelPesoDelComparador() {
        assertEquals("2026-08-24", FotosProgreso.desdePesoComparador(listOf("2026-11-16", "2026-09-02", "2026-10-05", "mal", "")))
        assertEquals("2026-08-24", FotosProgreso.desdePesoComparador(listOf("2026-08-31")))
        assertNull(FotosProgreso.desdePesoComparador(emptyList()))
        // Hoy 19/11: Salud trae desde el 21/09.
        assertTrue(FotosProgreso.necesitaPesoComparador("2026-09-20", "2026-11-19"))
        assertTrue(!FotosProgreso.necesitaPesoComparador("2026-09-21", "2026-11-19"))
    }
}

class AvisoFotosTest {
    @Test
    fun apareceSoloSiFaltanYElServidorYaContesto() {
        assertTrue(FotosProgreso.mostrarAviso(true, emptySet()))
        assertTrue(FotosProgreso.mostrarAviso(true, setOf("frente", "perfil")))
        assertFalse(FotosProgreso.mostrarAviso(true, setOf("frente", "perfil", "espalda")))
        assertFalse(FotosProgreso.mostrarAviso(false, emptySet()), "sin saber qué hay no se dice nada")
    }

    @Test
    fun elTextoEsElAprobado() {
        assertEquals("Tus fotos de la semana", FotosProgreso.AVISO_TITULO)
        assertEquals("Esta semana todavía no subiste tus fotos. Sacalas en el mismo lugar y con la misma luz que siempre, con la misma ropa, el celu vertical a la altura del ombligo y a 2 o 3 metros. Frente, perfil y espalda. Así vemos bien cómo venís", FotosProgreso.AVISO_CUERPO)
    }
}

/** Gemelo de `ProgresoEnAustraliaTests`: un alumno en Australia ve la sesión el día que la hizo. */
class ProgresoEnAustraliaTest {
    private val sidney = ZoneId.of("Australia/Sydney")

    /**
     * Las 6:10 del martes 10/11 en Sídney son las 19:10 UTC del lunes 9/11: la web agrupaba por la fecha UTC y la mostraba un
     * día atrás (hasta el 19/9). Las nativas usan la fecha local del teléfono.
     */
    @Test
    fun laSesionDeLaMananaNoQuedaUnDiaAtras() {
        val filas = listOf(reg("2026-11-09T19:40:00+00:00", 82.5), reg("2026-11-09T19:10:00.123456+00:00", 80.0))
        assertEquals("2026-11-10", FechaLocal.de("2026-11-09T19:10:00+00:00", sidney))
        assertEquals("2026-11-10", HistorialEntreno.fechaLocal("2026-11-09T19:10:00+00:00", sidney))
        assertEquals(setOf("2026-11-10"), ProgresoEjercicio.sesiones(filas, sidney).toSet())
        assertEquals(mapOf("2026-11-10" to 82.5), ProgresoSemana.ejercicio("x", filas, sidney).sesiones)
        assertEquals("1 sesión entrenada esta semana", ProgresoSemana.linea(listOf(ProgresoSemana.ejercicio("x", filas, sidney)), "2026-11-10")?.texto)
    }

    /** Dos series del mismo día local que caen en dos fechas UTC siguen siendo una sesión. */
    @Test
    fun unaSesionQueCruzaLaMedianocheUtcEsUna() {
        val filas = listOf(reg("2026-11-10T00:30:00+00:00", 80.0), reg("2026-11-09T23:50:00+00:00", 80.0))
        assertEquals(setOf("2026-11-10"), ProgresoEjercicio.sesiones(filas, sidney).toSet())
    }
}
