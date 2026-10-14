package com.pumpteam.mypump.modelos

import java.nio.file.Files
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

// Gemelo de DecodificacionTests.swift: las respuestas reales grabadas, los planes reales (privados) y la forma rota.

private fun fixture(cuenta: String, rpc: String): JsonElement =
    Json.parseToJsonElement(Rutas.leer(Rutas.compartido("fixtures/$cuenta/$rpc.json")))

class FixturesTest {
    @ParameterizedTest
    @ValueSource(strings = ["test-nativa-real", "test-nativa-ios"])
    fun rutinaYDieta(cuenta: String) {
        val r = listaEstricta(fixture(cuenta, "get_rutina_activa"), RutinaActiva::desde)
        assertEquals(1, r.size)
        assertFalse(r[0].estructura.dias.isEmpty())
        assertTrue(r[0].estructura.dias.all { it.id != null && it.bloques.isNotEmpty() })
        val d = listaEstricta(fixture(cuenta, "get_dieta_activa"), DietaActiva::desde)
        assertEquals(1, d.size)
        assertFalse(d[0].estructura.comidas.isEmpty())
        assertTrue(d[0].estructura.comidas.all { it.opciones.isNotEmpty() })
    }

    @ParameterizedTest
    @ValueSource(strings = ["test-nativa-real", "test-nativa-ios"])
    fun todasLasLecturas(cuenta: String) {
        listaEstricta(fixture(cuenta, "get_cliente_info"), ClienteInfo::desde)
        val hist = listaEstricta(fixture(cuenta, "get_historico_por_clave"), RegistroHistorico::desde)
        assertFalse(hist.isEmpty())
        assertTrue(hist.all { it.clave != null && it.registradoEn.isNotEmpty() })
        listaEstricta(fixture(cuenta, "get_sesiones_semana"), Sesion::desde)
        listaEstricta(fixture(cuenta, "get_sesion_dia"), Sesion::desde)
        listaEstricta(fixture(cuenta, "get_habitos_dia"), HabitosDia::desde)
        listaEstricta(fixture(cuenta, "get_streak"), Racha::desde)
        assertEquals(30, listaEstricta(fixture(cuenta, "get_adherencia_30d"), DiaAdherencia::desde).size)
        listaEstricta(fixture(cuenta, "get_comidas_marcadas"), ComidaMarcada::desde)
        listaEstricta(fixture(cuenta, "get_comidas_libres"), ComidaLibre::desde)
        listaEstricta(fixture(cuenta, "get_food_swaps"), FoodSwap::desde)
        listaEstricta(fixture(cuenta, "get_custom_foods"), AlimentoPropio::desde)
        listaEstricta(fixture(cuenta, "get_cliente_prefs"), PreferenciasCliente::desde)
        listaEstricta(fixture(cuenta, "get_comentarios"), Comentario::desde)
        listaEstricta(fixture(cuenta, "get_chat"), MensajeChat::desde)
        val salud = listaEstricta(fixture(cuenta, "get_salud"), FilaSalud::desde)
        assertTrue(salud.all { it.fecha.isNotEmpty() && it.tipo.isNotEmpty() })
        listaEstricta(fixture(cuenta, "get_recuperacion"), Recuperacion::desde)
        listaEstricta(fixture(cuenta, "get_conexiones"), Conexion::desde)
        listaEstricta(fixture(cuenta, "get_checkin_semana"), CheckinSemana::desde)
        listaEstricta(fixture(cuenta, "get_fotos_progreso"), FotoProgreso::desde)
        // `boolean` o null (null cuenta como true en la web).
        val mostrar = fixture(cuenta, "get_mostrar_recuperacion")
        assertTrue(mostrar is JsonPrimitive && (mostrar.content == "true" || mostrar.content == "false" || mostrar.content == "null"))
    }

    @Test
    fun registrosDeUnaSesion() {
        val regs = listaEstricta(fixture("test-nativa-real", "get_registros_sesion"), RegistroSesion::desde)
        assertFalse(regs.isEmpty())
        assertTrue(regs.all { it.ejercicioId.isNotEmpty() && it.serie >= 1 })
        val estados = listaEstricta(fixture("test-nativa-real", "get_ejercicios_estado"), EstadoEjercicio::desde)
        assertTrue(estados.all { it.ejercicioId.isNotEmpty() })
    }

    @Test
    fun formaRealDelCerebro() {
        val r = listaEstricta(fixture("test-nativa-real", "get_rutina_activa"), RutinaActiva::desde)[0]
        val ejercicios = r.estructura.dias.flatMap { d -> d.bloques.flatMap { it.ejercicios } }
        assertTrue(ejercicios.all { it.progresion.isNotEmpty() })
        assertTrue(ejercicios.any { it.imagenes?.eccentric != null })
        assertTrue(ejercicios.any { it.catalogoSlug != null })
        assertEquals(0, r.estructura.semanaOffset)
        assertEquals(1, r.estructura.fase)
        // series null y rir null en cardio: tienen que llegar como null, no romper.
        assertTrue(ejercicios.any { it.tipo == "cardio" && it.progresion.first().series == null })
    }

    @Test
    fun laDemoDeLaWeb() {
        val rutina = EstructuraRutina.desde(Json.parseToJsonElement(Rutas.leer(Rutas.compartido("demo/rutina.json"))))
        assertTrue(rutina.dias.isNotEmpty() && rutina.dias.all { it.bloques.isNotEmpty() })
        // La demo usa los campos viejos (sin progresión por semana).
        assertTrue(rutina.dias.flatMap { d -> d.bloques.flatMap { it.ejercicios } }.any { it.series != null && it.reps != null })
        val dieta = EstructuraDieta.desde(Json.parseToJsonElement(Rutas.leer(Rutas.compartido("demo/dieta.json"))))
        // Sin `macros_target` a propósito (f7aa713): el de SAMPLE_DIET (3.200 kcal) no cierra con sus opciones A y la
        // nativa marcaba "−23 %" en lo que ve la revisión de la tienda. normalizarDieta usa la suma de la opción A.
        assertTrue(dieta.comidas.isNotEmpty() && dieta.macrosTarget == null)
        assertTrue(dieta.comidas.all { c -> c.opciones.all { o -> o.alimentos.all { it.nombre.isNotEmpty() } } })
    }
}

/**
 * Las estructuras de TODOS los planes activos (leídas de la base, fuera del repo). Si no están, se saltea: en CI o en
 * otra Mac no existen. La decodificación tolerante no puede perder nada válido: se cuenta contra el JSON crudo.
 */
class PlanesRealesTest {
    private val carpeta = Rutas.carpetaPrivada.resolve("estructuras")

    private fun crudos(archivo: String): List<JsonElement> = (Json.parseToJsonElement(Rutas.leer(carpeta.resolve(archivo))) as JsonArray)

    private fun objetos(e: JsonElement?): List<JsonObject> = (e as? JsonArray)?.filterIsInstance<JsonObject>() ?: emptyList()

    @Test
    fun rutinasNoPierdenNada() {
        assumeTrue(Files.isDirectory(carpeta), "sin estructuras privadas")
        for (archivo in listOf("rutinas.json", "rutinas-en-cola.json")) {
            val crudas = crudos(archivo)
            val decodificadas = crudas.map(EstructuraRutina::desde)
            assertEquals(crudas.size, decodificadas.size)
            for ((dec, cruda) in decodificadas.zip(crudas)) {
                val dias = objetos(cruda.jsonObject["dias"])
                if (cruda.jsonObject["dias"] !is JsonArray) continue
                assertEquals(dias.size, dec.dias.size)
                for ((d, dc) in dec.dias.zip(dias)) {
                    val bloques = objetos(dc["bloques"])
                    assertEquals(bloques.size, d.bloques.size)
                    for ((b, bc) in d.bloques.zip(bloques)) {
                        val ejercicios = objetos(bc["ejercicios"])
                        assertEquals(ejercicios.size, b.ejercicios.size)
                        for ((e, ec) in b.ejercicios.zip(ejercicios)) {
                            assertTrue(e.id.isNotEmpty() && e.nombre.isNotEmpty(), "ejercicio sin id o nombre: $ec")
                            assertEquals(objetos(ec["progresion"]).size, e.progresion.size)
                        }
                    }
                }
            }
        }
    }

    @Test
    fun dietasNoPierdenNada() {
        assumeTrue(Files.isDirectory(carpeta), "sin estructuras privadas")
        val crudas = crudos("dietas.json")
        val decodificadas = crudas.map(EstructuraDieta::desde)
        assertEquals(crudas.size, decodificadas.size)
        for ((dec, cruda) in decodificadas.zip(crudas)) {
            val comidas = objetos(cruda.jsonObject["comidas"])
            assertEquals(comidas.size, dec.comidas.size)
            for ((com, cc) in dec.comidas.zip(comidas)) {
                val ops = objetos(cc["options"])
                assertEquals(ops.size, com.opciones.size)
                for ((op, oc) in com.opciones.zip(ops)) {
                    assertEquals(objetos(oc["foods"]).size, op.alimentos.size)
                    assertTrue(op.alimentos.all { it.nombre.isNotEmpty() && it.kcal != null })
                }
            }
        }
    }
}

class ToleranciaTest {
    @Test
    fun bloqueNullYReemplazaTexto() {
        val json = """
        {"dias":[{"id":"d4","n":"4","nombre":"Pierna","reemplaza":"d2","bloques":[null,{"titulo":"B1","ejercicios":[
          {"id":"x-d4-0","nombre":"Sentadilla","series":"4","reps":8,"descanso_segundos":0,"progresion":[null,{"semana":1,"series":null,"reps":"6-8","rir":null,"titulo":"S1"}]},
          "basura"
        ]}]}],"semanas_total":"12"}
        """
        val e = EstructuraRutina.desde(Json.parseToJsonElement(json))
        assertEquals(12, e.semanasTotal)
        assertEquals(4, e.dias[0].n)
        assertEquals(listOf("d2"), e.dias[0].reemplaza)
        assertEquals(1, e.dias[0].bloques.size)
        val x = e.dias[0].bloques[0].ejercicios
        assertEquals(1, x.size)
        assertTrue(x[0].series == 4 && x[0].reps == "8" && x[0].descansoSegundos == 0)
        assertTrue(x[0].progresion.size == 1 && x[0].progresion[0].series == null)
    }

    @Test
    fun foodDataSeConservaEntero() {
        val json = """[{"comida_id":"desayuno","opt_idx":1,"food_idx":2,"food_data":{"name":"Ricota","qty":150,"_orig":{"name":"Queso","qty":60,"unit":"g"},"_dev":0.03}}]"""
        val s = listaEstricta(json, FoodSwap::desde)[0]
        assertEquals("Queso", s.foodData["_orig"]?.get("name")?.comoTexto)
        val vuelta = s.foodData.serializar()
        assertEquals(s.foodData, ValorJson.parsear(vuelta))
        // Los números salen como en JSON.stringify: 150, no 150.0.
        assertTrue(vuelta.contains("\"qty\":150,") && vuelta.contains("\"_dev\":0.03"), vuelta)
    }

    @Test
    fun unaRespuestaConFormaInesperadaEsUnError() {
        assertThrows(ErrorDecodificacion::class.java) { listaEstricta("""[{"id":"x"}, 5]""", RutinaActiva::desde) }
        assertThrows(ErrorDecodificacion::class.java) { listaEstricta("""{"id":"x"}""", RutinaActiva::desde) }
    }

    @Test
    fun estructuraQueNoEsObjetoQuedaVacia() {
        val r = RutinaActiva.desde(Json.parseToJsonElement("""{"id": 7, "estructura": "rota", "semana_actual": null}"""))
        assertEquals("7", r.id)
        assertEquals(EstructuraRutina(), r.estructura)
        assertEquals(1, r.semanaActual)
        assertEquals(1, r.version)
        assertFalse(r.tieneSiguiente)
    }
}

/** Los lectores tolerantes, caso por caso (lo esperado es lo que hace `Decodificacion.swift`). */
class LectoresTest {
    private fun o(json: String) = Json.parseToJsonElement(json).jsonObject

    @Nested
    inner class Enteros {
        @Test
        fun numerosYTextos() {
            val x = o("""{"a":3,"b":3.0,"c":3.7,"d":-3.7,"e":"12","f":" 12 ","g":"1.0","h":"+5","i":true,"j":null,"k":"١٢","l":"12\n","m":1e20}""")
            assertEquals(3, x.entero("a"))
            assertEquals(3, x.entero("b"))
            assertEquals(3, x.entero("c"))          // Int(3.7) de Swift trunca
            assertEquals(-3, x.entero("d"))
            assertEquals(12, x.entero("e"))
            assertEquals(12, x.entero("f"))
            assertNull(x.entero("g"))               // Int("1.0") de Swift no lo acepta
            assertEquals(5, x.entero("h"))
            assertNull(x.entero("i"))               // un booleano no es un número
            assertNull(x.entero("j"))
            assertNull(x.entero("k"))               // dígitos árabes: Swift solo acepta ASCII
            assertNull(x.entero("l"))               // el salto de línea no se recorta (.whitespaces)
            assertNull(x.entero("m"))               // fuera de rango: no hay entero (Swift se caería)
            assertNull(x.entero("no-esta"))
        }
    }

    @Test
    fun decimales() {
        val x = o("""{"a":1.5,"b":"1,5","c":" 2.25 ","d":"abc","e":"0x10","f":"inf","g":true,"h":"1.5f","i":"-.5"}""")
        assertEquals(1.5, x.decimal("a"))
        assertEquals(1.5, x.decimal("b"))
        assertEquals(2.25, x.decimal("c"))
        assertNull(x.decimal("d"))
        assertEquals(16.0, x.decimal("e"))
        assertEquals(Double.POSITIVE_INFINITY, x.decimal("f"))
        assertNull(x.decimal("g"))
        assertNull(x.decimal("h"))              // el sufijo de Java no vale en Swift
        assertEquals(-0.5, x.decimal("i"))
    }

    @Test
    fun textos() {
        val x = o("""{"a":"8-10","b":10,"c":7.5,"d":1e-7,"e":true,"f":null,"g":["a",null,"b"],"h":"d2","i":["a",5],"j":{}}""")
        assertEquals("8-10", x.texto("a"))
        assertEquals("10", x.texto("b"))
        assertEquals("7.5", x.texto("c"))
        assertEquals("1e-7", x.texto("d"))      // como String(x) de JS
        assertNull(x.texto("e"))
        assertNull(x.texto("f"))
        assertEquals(listOf("a", "b"), x.textos("g"))
        assertEquals(listOf("d2"), x.textos("h"))
        assertNull(x.textos("i"))               // un elemento que no es texto invalida el array, como [String?]
        assertNull(x.textos("j"))
    }

    @Test
    fun booleanos() {
        val x = o("""{"a":true,"b":0,"c":2,"d":"SÍ","e":"sí","f":"no","g":0.5,"h":"1","i":null}""")
        assertEquals(true, x.booleano("a"))
        assertEquals(false, x.booleano("b"))
        assertEquals(true, x.booleano("c"))
        assertEquals(true, x.booleano("d"))
        assertEquals(true, x.booleano("e"))     // "sí" con la tilde suelta: Swift compara por equivalencia canónica
        assertEquals(false, x.booleano("f"))
        assertNull(x.booleano("g"))
        assertEquals(true, x.booleano("h"))
        assertNull(x.booleano("i"))
    }

    @Test
    fun listasToleranYEnterosEstrictos() {
        val m = ComidaMarcada.desde(Json.parseToJsonElement("""{"comida_id":"c1","foods_excluidos":[0,2.0,2.5,"3",null,true,4]}"""))
        assertEquals(listOf(0, 2, 4), m.foodsExcluidos)
        val e = EstructuraDieta.desde(Json.parseToJsonElement("""{"comidas":{"no":"es array"},"tipos_dia":null}"""))
        assertTrue(e.comidas.isEmpty() && e.tiposDia.isEmpty())
    }

    @Test
    fun catalogoSoloTextos() {
        val c = EntradaCatalogoEjercicio.desde(
            Json.parseToJsonElement("""{"slug_en":5,"name_en":"Row","aliases_es":["remo",5,null],"equipment":null}"""),
        )
        assertNull(c.slugEn)                    // la web compara con ===: un número nunca es igual a un texto
        assertEquals(listOf("remo"), c.aliasesEs)
        assertNull(c.equipment)
        assertNull(EntradaCatalogoEjercicio.desde(Json.parseToJsonElement("""{"aliases_es":"remo"}""")).aliasesEs)
    }

    @Test
    fun estimacionDelPlatoEsTodoONada() {
        val bien = EstimacionPlato.desde(Json.parseToJsonElement("""{"alimentos":[{"nombre":"Milanesa","gramos":"205"}],"kcal":451}"""))
        assertEquals(205.0, bien.alimentos.single().gramos)
        val rota = EstimacionPlato.desde(Json.parseToJsonElement("""{"alimentos":[{"nombre":"Milanesa"}, 5]}"""))
        assertTrue(rota.alimentos.isEmpty())
        val etiqueta = LecturaEtiqueta.desde(Json.parseToJsonElement("""{"nombre":"Yogur","porcion_g":"30","kcal":75,"confianza":"alta"}"""))
        assertEquals(30.0, etiqueta.porcionG)
    }

    @Test
    fun valorJsonComoJs() {
        assertEquals(ValorJson.Numero(0.0), ValorJson.Numero(-0.0))
        assertEquals(ValorJson.Numero(80.0), ValorJson.parsear("80"))
        assertEquals("""{"a":[1,0.5,null,true,"x"],"b":{}}""", ValorJson.parsear("""{"a":[1.0,0.5,null,true,"x"],"b":{}}""").serializar())
        assertEquals("null", ValorJson.Numero(Double.NaN).serializar())   // JSON.stringify(NaN)
    }
}
