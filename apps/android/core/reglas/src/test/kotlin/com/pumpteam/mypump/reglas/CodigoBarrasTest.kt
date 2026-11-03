package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El código de barras (2.1, S3): el número del escáner, la respuesta de Open Food Facts llevada a un alimento y la caché.
 * Los mismos vectores que iOS (`apps/shared/vectores/barras_off.json`), con respuestas reales de productos argentinos.
 */
class CodigoBarrasTest {
    private val vectores = Vectores.json(Vectores.publico("barras_off"))

    @Test
    fun losCodigosSeNormalizanComoLosVectores() {
        val casos = vectores["codigos"]!!.jsonArray
        assertTrue(casos.size >= 15)
        for (c in casos) {
            val o = c.jsonObject
            val texto = o["texto"]!!.jsonPrimitive.content
            val upcE = o["upcE"]!!.jsonPrimitive.booleanOrNull!!
            assertEquals(o["esperado"]?.jsonPrimitive?.contentOrNull, CodigoBarras.normalizar(texto, upcE), "$texto upcE=$upcE")
        }
    }

    /** Lo que sale de una lectura, con la forma de los vectores. */
    private fun json(l: CodigoBarras.Lectura): Map<String, Any> = when (l) {
        CodigoBarras.Lectura.NoEncontrado -> mapOf("estado" to "noEncontrado")
        is CodigoBarras.Lectura.Encontrado -> buildMap {
            val p = l.producto
            put("estado", "encontrado")
            put("nombre", p.nombre)
            put("por100", mapOf("kcal" to p.por100.kcal, "p" to p.por100.p, "c" to p.por100.c, "g" to p.por100.g))
            if (p.medida != null && p.gramosMedida != null) put("medida", mapOf("nombre" to p.medida, "gramos" to p.gramosMedida))
        }
        is CodigoBarras.Lectura.Incompleto -> buildMap {
            val x = l.parcial
            put("estado", "incompleto")
            put("motivo", x.motivo.valor)
            x.nombre?.let { put("nombre", it) }
            x.kcal?.let { put("kcal", it) }
            x.p?.let { put("p", it) }
            x.c?.let { put("c", it) }
            x.g?.let { put("g", it) }
        }
    }

    /** El JSON de los vectores como mapas, con los números como Double. */
    private fun comoMapa(o: JsonObject): Map<String, Any> = o.mapValues { (_, v) ->
        when (v) {
            is JsonObject -> comoMapa(v)
            is JsonPrimitive -> if (v.isString) v.content else v.doubleOrNull!!
            else -> error("inesperado: $v")
        }
    }

    @Test
    fun lasRespuestasDeOpenFoodFactsDanLoMismoQueLosVectores() {
        val casos = vectores["productos"]!!.jsonArray
        assertTrue(casos.count { it.jsonObject["real"]!!.jsonPrimitive.booleanOrNull == true } >= 10)
        for (c in casos) {
            val o = c.jsonObject
            val codigo = o["codigo"]!!.jsonPrimitive.content
            if (o["real"]!!.jsonPrimitive.booleanOrNull == true) assertEquals(codigo, CodigoBarras.normalizar(codigo), "$codigo no es un código válido")
            val l = CodigoBarras.leer(ValorJson.desde(o["respuesta"]!!), codigo)
            assertEquals(comoMapa(o["esperado"]!!.jsonObject), json(l), o["caso"]!!.jsonPrimitive.content)
            if (l is CodigoBarras.Lectura.Encontrado) {
                assertEquals(codigo, l.producto.codigo)
                assertEquals(AlimentoAgregado.Origen.BARRAS, l.producto.candidato.origen)
                assertEquals(codigo, l.producto.candidato.codigo)
            }
        }
    }

    @Test
    fun elEscaneadoVaALaHojaConSuPorcionYQuedaConElCodigo() {
        val c = CodigoBarras.Producto("77916501", "Cereal Mix Original (Arcor)", MacrosPor100(402.0, 6.5, 66.0, 13.0), "barra", 23.0).candidato
        assertEquals(listOf(AgregadosComida.Medida.GRAMO, AgregadosComida.Medida("barra", 23.0)), AgregadosComida.medidas(c))
        val (q, m) = AgregadosComida.inicial(c)
        assertEquals(1.0, q)
        assertEquals("barra", m.nombre)
        val a = AgregadosComida.agregado(c, 2.0, m, 1)
        assertEquals(46.0, a.gramos)
        assertEquals(185.0, a.kcal)
        assertEquals(AlimentoAgregado.Origen.BARRAS, a.origen)
        assertEquals("77916501", a.codigo)
        val y = CodigoBarras.Producto("7791337006355", "Yogur", MacrosPor100(82.0, 7.0, 6.3, 3.2), "porción", 200.0).candidato
        assertEquals(AgregadosComida.Medida("porción", 200.0), AgregadosComida.medidas(y).last())
        val propio = AgregadosComida.Candidato("Pan", MacrosPor100(250.0, 9.0, 48.0, 3.0), "porcion", 30.0, AlimentoAgregado.Origen.PROPIO)
        assertEquals("porción", AgregadosComida.medidas(propio).last().nombre)
    }

    /** El agregado con origen «barras» y su código va y vuelve; uno con un código roto conserva todo menos el código. */
    @Test
    fun elAgregadoConCodigoVaYVuelve() {
        val a = AlimentoAgregado("Cereal Mix", 1.0, "barra", 23.0, 23.0, 92.0, 1.5, 15.2, 3.0, MacrosPor100(402.0, 6.5, 66.0, 13.0),
            AlimentoAgregado.Origen.BARRAS, 5, "77916501")
        val v = a.aValor()
        assertEquals("barras", v["origen"]?.comoTexto)
        assertEquals("77916501", v["codigo"]?.comoTexto)
        assertEquals(a, AlimentoAgregado.desde(ValorJson.parsear(v.serializar())))
        val roto = ValorJson.Objeto((v as ValorJson.Objeto).campos + ("codigo" to ValorJson.Texto("77a16501")))
        val r = AlimentoAgregado.desde(roto)!!
        assertNull(r.codigo)
        assertEquals(92.0, r.kcal)
        // Sin código (lo de antes) queda igual que antes: sin la clave.
        assertNull(a.copy(codigo = null).aValor()["codigo"])
        // Un origen que no se conoce (lo que hace una 2.0.3 con «barras») cae en BASE sin descartar el agregado.
        val raro = ValorJson.Objeto(v.campos + ("origen" to ValorJson.Texto("otro")))
        assertEquals(AlimentoAgregado.Origen.BASE, AlimentoAgregado.desde(raro)!!.origen)
    }

    @Test
    fun laCacheVenceSegunLoQueEncontro() {
        val dia = CacheCodigos.DIA_MS
        val prod = CodigoBarras.Producto("1", "X", MacrosPor100(1.0, 0.0, 0.0, 0.0), null, null)
        val c = CacheCodigos()
        c.guardar("a", CodigoBarras.Lectura.Encontrado(prod), 0)
        c.guardar("b", CodigoBarras.Lectura.NoEncontrado, 0)
        c.guardar("c", CodigoBarras.Lectura.Incompleto(CodigoBarras.Parcial("c", CodigoBarras.Parcial.Motivo.FALTAN_DATOS)), 0)
        assertEquals(CodigoBarras.Lectura.Encontrado(prod), c.vigente("a", 29 * dia))
        assertNull(c.vigente("a", 30 * dia))
        assertEquals(CodigoBarras.Lectura.NoEncontrado, c.vigente("b", dia - 1))
        assertNull(c.vigente("b", dia))
        assertNull(c.vigente("c", dia))
        assertNull(c.vigente("a", -1), "Un reloj que volvió atrás no da por vigente")
        assertNull(c.vigente("z", 0))

        val propio = prod.copy(propio = true)
        c.guardar("p", CodigoBarras.Lectura.Encontrado(propio), 0)
        c.guardar("p", CodigoBarras.Lectura.NoEncontrado, 1)
        c.guardar("p", CodigoBarras.Lectura.Encontrado(prod), 1)
        assertEquals(CodigoBarras.Lectura.Encontrado(propio), c.vigente("p", 3650 * dia))

        // Va y vuelve del disco.
        val leida = CacheCodigos.desde(ValorJson.parsear(c.aValor().serializar()))
        assertEquals(c.entradas, leida.entradas)
    }

    @Test
    fun laCacheTieneTopeYSeVanLasMasViejas() {
        val c = CacheCodigos()
        val propio = CodigoBarras.Producto("p", "X", MacrosPor100(1.0, 0.0, 0.0, 0.0), null, null, propio = true)
        c.guardar("p", CodigoBarras.Lectura.Encontrado(propio), 0)
        for (i in 1..CacheCodigos.MAXIMO + 5) c.guardar("k$i", CodigoBarras.Lectura.NoEncontrado, i.toLong())
        assertEquals(CacheCodigos.MAXIMO, c.entradas.size)
        assertNotNull(c.entradas["p"], "El propio, el más viejo, queda")
        assertNull(c.entradas["k1"])
        assertNull(c.entradas["k6"])
        assertNotNull(c.entradas["k7"])
    }

    @Test
    fun elPedidoVaConLosCamposYElAgente() {
        assertEquals(
            "https://world.openfoodfacts.org/api/v2/product/7791337006355.json?fields=product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,quantity",
            CodigoBarras.url("7791337006355"),
        )
        assertEquals("PumpTeam/2.1.0 (Android)", CodigoBarras.agenteUsuario("2.1.0", "Android"))
    }
}
