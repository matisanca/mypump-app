package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.VolumenMusculo
import java.time.Instant
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Volumen por músculo (2.1, S2) con los datos de la app (gemelo de VolumenDatosTests de iOS): el historial de Progreso
 * como registros, las series confirmadas hoy en el teléfono y el resumen de ModeloApp. Sin red.
 */
class VolumenDatosTest {
    private fun fila(clave: String, registradoEn: String, serie: Int = 1) =
        RegistroHistorico(clave, null, registradoEn, 60.0, 8, 1, serie, null, null)

    @Test
    fun cadaFilaDelHistorialEsUnaSerieConSuFechaLocal() {
        val historial = mapOf(
            "remo" to listOf(fila("remo", "2026-10-13T12:00:00+00:00")),
            // 01:30 UTC del 13 es el 12 a la noche en Buenos Aires.
            "jalon" to listOf(fila("jalon", "2026-10-13T01:30:00+00:00"), fila("jalon", "2026-10-13T01:30:00+00:00")),
            "viejo" to listOf(fila("viejo", "2026-10-13T12:00:00+00:00")),
        )
        val ejercicios = mapOf(
            "jalon" to VolumenDatos.Info("lats", "compuesto"),
            "remo" to VolumenDatos.Info("middle back", "compuesto"),
        )
        val r = VolumenDatos.registros(historial, ejercicios, zonaAR)
        // Claves en orden alfabético; van con su número y su clave (para no sumar de nuevo lo en vivo) y cada fila cuenta.
        assertEquals(listOf("jalon", "jalon", "remo", "viejo"), r.map { it.lugar })
        assertTrue(r.all { it.serie == 1 && it.clave == it.lugar })
        assertEquals(listOf("2026-10-12", "2026-10-12", "2026-10-13", "2026-10-13"), r.map { it.fecha })
        assertEquals(listOf("lats", "lats", "middle back", null), r.map { it.musculo })
        assertEquals("compuesto", r.first().tipo)
        // Una clave que ya no está en el plan queda sin músculo ni tipo.
        assertNull(r.last().tipo)
        // En UTC la fecha es otra: se usa la zona que se pasa.
        assertEquals("2026-10-13", VolumenDatos.registros(historial, ejercicios, ZoneId.of("UTC")).first().fecha)
    }

    @Test
    fun lasSeriesConfirmadasHoyConElMusculoDelCatalogo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        assertTrue(m.registrosVolumenEnVivo.isEmpty())
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        m.escribir("jal-d1-0", 1, "reps", "9")
        m.escribir("jal-d1-0", 1, "kg", "60")
        m.confirmarSerie("jal-d1-0", 1) { true }
        val r = m.registrosVolumenEnVivo
        val jalon = m.dia.value.lista.first { it.id == "jal-d1-0" }
        assertEquals(2, r.size, "$r")
        assertEquals(listOf(1, 2), r.map { it.serie })
        assertTrue(r.all { it.lugar == "jal-d1-0" && it.fecha == "2026-10-14" && it.tipo == "compuesto" && it.clave == ClaveEjercicio.de("Jalón al pecho") })
        assertEquals("lats", m.musculo(jalon))
        assertTrue(r.all { it.musculo == "lats" })
        // Con la regla del kit: 2 de dorsales hoy y en la semana.
        val resumen = VolumenMusculo.calcular(emptyList(), r, "2026-10-14")
        assertEquals(2, resumen.totalHoy)
        assertEquals("Dorsales", resumen.filasDeHoy.single().nombre)
    }

    /** Revisión del 3-nov: la serie tocada queda con la fecha del toque, aunque el día del plan se mire mañana. */
    @Test
    fun laSerieTocadaQuedaConLaFechaDelToque() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        for (i in 0..1) {
            m.escribir("jal-d1-0", i, "reps", "10")
            m.escribir("jal-d1-0", i, "kg", "60")
            m.confirmarSerie("jal-d1-0", i) { true }
        }
        b.reloj.ms += 86_400_000
        val r = m.registrosVolumenEnVivo
        assertTrue(r.size == 2 && r.all { it.fecha == "2026-10-14" }, "$r")
        val v = VolumenMusculo.calcular(emptyList(), r, "2026-10-15")
        assertEquals(2, v.total)
        assertEquals(0, v.totalHoy)
        // Corregirla (el lápiz) no le cambia la fecha: el servidor conserva el `registrado_en`.
        m.editarSerie("jal-d1-0", 0)
        m.confirmarSerie("jal-d1-0", 0) { true }
        assertEquals("2026-10-14", m.registrosVolumenEnVivo.first().fecha)
    }

    /** La sesión del lunes mirada el miércoles: cada serie con su `registrado_en`, y no se cuenta dos veces. */
    @Test
    fun lasSeriesDelServidorTraenSuRegistradoEnYNoSeCuentanDosVeces() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-lunes"))
        b.servidor.cuando(
            "get_registros_sesion",
            """[{"ejercicio_id":"jal-d1-0","serie_numero":1,"peso_kg":60,"reps_realizadas":10,"rir_real":1,"ejercicio_nombre":"Jalón al pecho","notas":null,"registrado_en":"2026-10-12T22:00:00+00:00"},
               {"ejercicio_id":"jal-d1-0","serie_numero":2,"peso_kg":60,"reps_realizadas":9,"rir_real":1,"ejercicio_nombre":"Jalón al pecho","notas":null,"registrado_en":"2026-10-12T22:03:00+00:00"},
               {"ejercicio_id":"rem-d1-1","serie_numero":1,"peso_kg":50,"reps_realizadas":8,"rir_real":1,"ejercicio_nombre":"Remo con barra","notas":null}]""",
        )
        val m = b.modelo()
        m.restaurarSesion()
        val r = m.registrosVolumenEnVivo
        // La que no trae fecha no va en vivo (ya está en el historial).
        assertEquals(listOf("jal-d1-0", "jal-d1-0"), r.map { it.lugar })
        assertTrue(r.all { it.fecha == "2026-10-12" }, "$r")
        val clave = ClaveEjercicio.de("Jalón al pecho")
        val historial = listOf(1, 2).map { VolumenMusculo.Registro("lats", "compuesto", "2026-10-12", clave, it, clave) }
        val v = VolumenMusculo.calcular(historial, r, "2026-10-14")
        assertEquals(2, v.total, "las del lunes contaban dos veces")
        assertEquals(0, v.totalHoy, "y como de hoy")
    }

    /** Otro arranque sin red: la serie vuelve de la cola con la fecha en que se encoló. */
    @Test
    fun loQueQuedoEnLaColaVaConLaFechaDeLaCola() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        val op = b.cola.operaciones().first { it.kind == "carga" }
        b.servidor.sinRed("get_sesion_dia")
        val otro = b.modelo()
        otro.restaurarSesion()
        val esperada = FechaLocal.hoy(Instant.ofEpochMilli(op.ts.toLong()), zonaAR)
        assertEquals(listOf(esperada), otro.registrosVolumenEnVivo.map { it.fecha })
    }

    @Test
    fun otraSesionNoHeredaLasFechas() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.anotarFecha("jal-d1-0", 1, "2026-07-20")
        assertEquals(1, m.fechasSeries.value.size)
        b.servidor.cuando("get_sesion_dia", "[]")
        m.restaurarSesion()
        assertTrue(m.fechasSeries.value.isEmpty(), "una clave repetida heredaba la fecha de la sesión anterior")
    }

    @Test
    fun unLugarDeTrabajoLeGanaAlCalentamientoConElMismoNombre() {
        assertTrue(VolumenDatos.esDeTrabajoMejor("calentamiento", "compuesto"))
        assertTrue(VolumenDatos.esDeTrabajoMejor("cardio", null))
        assertTrue(!VolumenDatos.esDeTrabajoMejor("compuesto", "calentamiento"))
        assertTrue(!VolumenDatos.esDeTrabajoMejor("compuesto", "aislamiento"))
        assertTrue(!VolumenDatos.esDeTrabajoMejor("calentamiento", "cardio"))
    }

    @Test
    fun elResumenDeLaAppJuntaElHistorialPorClave() = enUnHilo { alcance ->
        val banca = ClaveEjercicio.de("Press banca")
        val jalon = ClaveEjercicio.de("Jalón al pecho")
        fun fila(clave: String, fecha: String, n: Int) =
            """{"clave":"$clave","registrado_en":"${fecha}T15:00:00+00:00","peso_kg":60,"reps_realizadas":8,"rir_real":1,"serie_numero":$n,"notas":null,"ejercicio_nombre":null}"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to "[${filaRutina()}]"
                "mypump_ejercicios_catalogo" -> 200 to CATALOGO
                "mypump_get_historico_por_clave" -> 200 to "[" + listOf(
                    fila(banca, "2026-10-13", 1), fila(banca, "2026-10-13", 2), fila(banca, "2026-10-14", 1),
                    fila(jalon, "2026-10-07", 1),
                    fila(jalon, "2026-09-29", 1),   // hace dos semanas: no cuenta
                ).joinToString(",") + "]"
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("volumen-app"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        val ahora = Instant.ofEpochMilli(AHORA.toLong())   // miércoles 14-oct-2026
        // Sin el historial cargado no hay nada (y hoy no se confirmó nada en el teléfono).
        assertEquals(0, m.volumenPorMusculo(zonaAR, ahora).total)
        m.cargarProgreso()
        val entreno = m.entreno.value!!
        val dias = m.rutina.value!!.estructura.dias
        val press = dias[1].bloques[0].ejercicios[0]
        val jal = dias[0].bloques[0].ejercicios[0]
        val r = m.volumenPorMusculo(zonaAR, ahora)
        assertEquals("2026-10-12", r.semana)
        assertEquals(3, r.total)
        assertEquals(1, r.totalAnterior)
        assertEquals(1, r.totalHoy)   // la del 14 (del historial: no hay nada en vivo)
        assertEquals("chest", entreno.musculo(press))
        assertEquals("lats", entreno.musculo(jal))
        val pecho = r.filas.first { it.musculo == "chest" }
        assertTrue(pecho.semana == 3 && pecho.anterior == 0 && pecho.hoy == 1, "$pecho")
        val espalda = r.filas.first { it.musculo == "lats" }
        assertTrue(espalda.semana == 0 && espalda.anterior == 1, "$espalda")
    }

    private companion object {
        /** El catálogo de prueba más el press banca (pecho), como lo da `mypump_ejercicios_catalogo`. */
        const val CATALOGO = """[{"slug_en":"Wide-Grip_Lat_Pulldown","name_en":"Wide-Grip Lat Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
            {"slug_en":"Barbell_Bench_Press","name_en":"Barbell Bench Press","name_normalized":"press banca","primary_muscle":"chest","equipment":"barbell","patron_movimiento":"empuje_horizontal"}]"""
    }
}
