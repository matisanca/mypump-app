package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de WinsTests.swift: «Récords y logros» (2.3.0) contra los vectores de `wins.json` (todos los casos y los textos). */
class WinsTest {
    private val v by lazy { Vectores.json(Vectores.publico("wins")) }
    private fun marcas(o: JsonObject, k: String) =
        o[k]!!.jsonArray.map { it.jsonObject }.map { RecordSerie.Marca(it["kg"]!!.jsonPrimitive.double, it["reps"]!!.jsonPrimitive.int) }

    @Test
    fun recordsDelDia() {
        val casos = v["records"]!!.jsonArray.map { it.jsonObject }
        assertTrue(casos.size >= 18)
        for (c in casos) {
            val n = c["nombre"]!!.jsonPrimitive.content
            val entrada = c["ejercicios"]!!.jsonArray.map { it.jsonObject }.map { e ->
                ReglasWins.Ejercicio(
                    e["clave"]!!.jsonPrimitive.content, e["nombre"]!!.jsonPrimitive.content, marcas(e, "anteriores"), marcas(e, "hoy"),
                    sinKg = e["sin_kg"]?.jsonPrimitive?.booleanOrNull ?: false, suficiente = e["suficiente"]?.jsonPrimitive?.booleanOrNull ?: true,
                )
            }
            val r = ReglasWins.records(entrada)
            val esp = c["salida"]!!.jsonArray.map { it.jsonObject }
            assertEquals(esp.size, r.size, n)
            for ((x, e) in r.zip(esp)) {
                assertEquals(e["tipo"]!!.jsonPrimitive.content, x.tipo.valor, n)
                assertEquals(e["clave"]!!.jsonPrimitive.content, x.clave, n)
                assertEquals(e["ejercicio"]!!.jsonPrimitive.content, x.ejercicio, n)
                assertEquals(e["kg"]!!.jsonPrimitive.double, x.kg, 1e-9, n)
                assertEquals(e["reps"]!!.jsonPrimitive.int, x.reps, n)
                assertEquals(e["antes_kg"]!!.jsonPrimitive.double, x.antesKg, 1e-9, n)
                assertEquals(e["antes_reps"]!!.jsonPrimitive.int, x.antesReps, n)
                assertEquals(e["delta"]!!.jsonPrimitive.double, x.delta, 1e-9, n)
                assertEquals(e["marca"]!!.jsonPrimitive.content, x.marca, n)
                assertEquals(e["chip"]!!.jsonPrimitive.content, x.chip, n)
                assertEquals(e["antes"]!!.jsonPrimitive.content, x.antes, n)
            }
        }
        assertEquals(v["tope"]!!.jsonPrimitive.int, ReglasWins.TOPE)
    }

    @Test
    fun textos() {
        val casos = v["textos"]!!.jsonArray.map { it.jsonObject }
        assertTrue(casos.size >= 4)
        for (c in casos) {
            val n = c["n"]!!.jsonPrimitive.int
            assertEquals(c["titulo"]!!.jsonPrimitive.content, ReglasWins.titulo(n))
            assertEquals(c["subtitulo"]!!.jsonPrimitive.content, ReglasWins.subtitulo(n))
            assertEquals(c["con_permiso"]!!.jsonPrimitive.content, ReglasWins.conPermiso(n))
        }
    }

    @Test
    fun textosFijos() {
        val f = v["fijos"]!!.jsonObject
        fun t(k: String) = f[k]!!.jsonPrimitive.content
        val propios = mapOf(
            "contarle" to ReglasWins.CONTARLE, "seguir" to ReglasWins.SEGUIR, "permiso_titulo" to ReglasWins.PERMISO_TITULO,
            "permiso_si" to ReglasWins.PERMISO_SI, "permiso_no" to ReglasWins.PERMISO_NO, "ajuste_seccion" to ReglasWins.AJUSTE_SECCION,
            "ajuste_interruptor" to ReglasWins.AJUSTE_INTERRUPTOR, "ajuste_pie" to ReglasWins.AJUSTE_PIE, "desactivado" to ReglasWins.DESACTIVADO,
            "sin_red" to ReglasWins.SIN_RED, "demo" to ReglasWins.DEMO, "racha_con_permiso" to ReglasWins.RACHA_CON_PERMISO,
        )
        // Todos los fijos del vector están cubiertos (si se suma uno, esta prueba lo pide).
        assertEquals(f.keys - "permiso_cuerpo", propios.keys)
        for ((k, texto) in propios) assertEquals(t(k), texto, k)
        assertEquals(f["permiso_cuerpo"]!!.jsonArray.map { it.jsonPrimitive.content }, ReglasWins.PERMISO_CUERPO)
        assertEquals(v["permiso_version"]!!.jsonPrimitive.int, ReglasWins.PERMISO_VERSION)
    }

    @Test
    fun hitosDeLaRacha() {
        assertEquals(v["hitos_racha"]!!.jsonArray.map { it.jsonPrimitive.int }, ReglasWins.HITOS_RACHA)
        val casos = v["racha"]!!.jsonArray.map { it.jsonObject }
        assertTrue(casos.size >= 18)
        for (c in casos) {
            val d = c["dias"]!!.jsonPrimitive.int
            assertEquals(c["es_hito"]!!.jsonPrimitive.boolean, ReglasWins.esHito(d), "$d días")
        }
    }

    @Test
    fun losDatosQueViajan() {
        val r = ReglasWins.records(
            listOf(ReglasWins.Ejercicio("remo con barra", "Remo con barra", listOf(RecordSerie.Marca(55.0, 8)), listOf(RecordSerie.Marca(57.5, 8)))),
        ).single()
        assertEquals("""{"ejercicio":"Remo con barra","kg":57.5,"reps":8,"antes_kg":55,"antes_reps":8}""", r.datos.serializar())
        assertEquals("""{"dias":7,"meta":9000}""", ReglasWins.datosRacha(7, 9000).serializar())
        assertEquals(ReglasWins.Tipo.RACHA_PASOS, ReglasWins.Tipo.desde("racha_pasos"))
        assertNull(ReglasWins.Tipo.desde("otro"))
        assertFalse(r.datos == ValorJson.Nulo)
    }

    @Test
    fun losTextosNoNombranLoProhibido() {
        val todos = (v["fijos"]!!.jsonObject.values.flatMap { e -> (e as? kotlinx.serialization.json.JsonArray)?.map { it.jsonPrimitive.content } ?: listOf(e.jsonPrimitive.content) } +
            ReglasWins.titulo(2) + ReglasWins.subtitulo(2) + ReglasWins.conPermiso(2)).joinToString(" ").lowercase()
        for (p in listOf("ia", "tu coach", "tu entrenador", "rir", "reserva", "entrega")) assertFalse(Regex("(?<![\\p{L}])$p(?![\\p{L}])").containsMatchIn(todos), p)
    }
}
