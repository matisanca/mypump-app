package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.reglas.ClaveEjercicio
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
        // Claves en orden alfabético; las dos filas iguales del jalón son dos series (van sin número).
        assertEquals(listOf("jalon", "jalon", "remo", "viejo"), r.map { it.lugar })
        assertTrue(r.all { it.serie == null })
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
        assertTrue(m.registrosVolumenHoy.isEmpty())
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        m.escribir("jal-d1-0", 1, "reps", "9")
        m.escribir("jal-d1-0", 1, "kg", "60")
        m.confirmarSerie("jal-d1-0", 1) { true }
        val r = m.registrosVolumenHoy
        val jalon = m.dia.value.lista.first { it.id == "jal-d1-0" }
        assertEquals(2, r.size, "$r")
        assertEquals(listOf(1, 2), r.map { it.serie })
        assertTrue(r.all { it.lugar == "jal-d1-0" && it.fecha == "2026-10-14" && it.tipo == "compuesto" })
        assertEquals("lats", m.musculo(jalon))
        assertTrue(r.all { it.musculo == "lats" })
        // Con la regla del kit: 2 de dorsales hoy y en la semana.
        val resumen = VolumenMusculo.calcular(emptyList(), r, "2026-10-14")
        assertEquals(2, resumen.totalHoy)
        assertEquals("Dorsales", resumen.filasDeHoy.single().nombre)
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
