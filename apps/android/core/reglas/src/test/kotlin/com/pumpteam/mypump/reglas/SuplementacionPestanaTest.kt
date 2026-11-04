package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.CompraSuplemento
import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.Suplementacion
import java.nio.file.Files
import java.nio.file.Paths
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La pestaña Suplementación: la agrupación (la de «Tu guía») y los textos de las etiquetas y del detalle. */
class SuplementacionPestanaTest {
    /** La muestra de la demo: el ejemplo del contrato (sección 10), ficticio. */
    private val demo: Suplementacion by lazy {
        val raiz = generateSequence(Paths.get("").toAbsolutePath()) { it.parent }.first { Files.isDirectory(it.resolve("apps/shared/demo")) }
        PlanSuplementacion.desde(Json.parseToJsonElement(Files.readString(raiz.resolve("apps/shared/demo/suplementacion.json"))))!!.suplementacion
    }

    private fun sup(json: String) = PlanSuplementacion.desde(Json.parseToJsonElement("""{"suplementacion":$json}"""))!!.suplementacion

    @Test
    fun tuDiaEnElOrdenDeDiaConLasTomas() {
        val v = SuplementacionVista.armar(demo)
        assertEquals(listOf("desayuno", "pre", "dormir"), v.momentos.map { it.id })
        assertEquals(listOf("Con el desayuno", "30 a 60 minutos antes de entrenar", "30 minutos antes de acostarte"), v.momentos.map { it.titulo })
        // Cada toma de Omega 3 va en su momento, con su cantidad.
        assertEquals(listOf("Creatina monohidrato" to "5 g", "Omega 3" to "1 g"), v.momentos[0].filas.map { it.nombre to it.cantidad })
        assertEquals(listOf("Cafeína"), v.momentos[1].filas.map { it.nombre })
        assertEquals(listOf("Omega 3" to "1 g", "Magnesio glicinato" to "400 mg"), v.momentos[2].filas.map { it.nombre to it.cantidad })
        // El que sale no va en el día: va en «Dejás de tomar», con su porqué.
        assertTrue(v.momentos.flatMap { it.filas }.none { it.nombre == "Multivitamínico" })
        assertEquals(listOf("Multivitamínico" to "Ya lo cubrís con la dieta"), v.sale.map { it.nombre to it.porQue })
        assertEquals("sale", v.sale[0].item.estado)
        // Cada fila lleva su ítem entero (para el detalle).
        assertEquals("200 mg", v.momentos[2].filas[1].item.antes)
    }

    @Test
    fun momentoDesconocidoAlFinalConSuNombre() {
        val s = sup(
            """{"dia":[{"id":"cena"}],"items":[
                {"nombre":"A","momento":"siesta","estado":"nuevo"},
                {"nombre":"B","momento":"cena","estado":"sigue"},
                {"nombre":"C","momento":"despertar"}
            ]}""",
        )
        val v = SuplementacionVista.armar(s)
        // Los de `dia`, después los conocidos que falten, después cualquier otro.
        assertEquals(listOf("cena", "despertar", "siesta"), v.momentos.map { it.id })
        // Sin `nombre` en `dia`: el texto propio de la app; uno desconocido, legible.
        assertEquals(listOf("Cena", "Al despertar", "Siesta"), v.momentos.map { it.titulo })
        assertEquals("Después de la siesta", SuplementacionVista.tituloMomento("siesta", sup("""{"dia":[{"id":"siesta","nombre":"Después de la siesta"}],"items":[{"nombre":"A","momento":"siesta"}]}""")))
    }

    @Test
    fun etiquetasDeEstado() {
        assertEquals("Nuevo", SuplementacionPestana.etiquetaEstado("nuevo"))
        // Sin estado = nuevo (contrato).
        assertEquals("Nuevo", SuplementacionPestana.etiquetaEstado(null))
        assertEquals("Cambia", SuplementacionPestana.etiquetaEstado("cambia"))
        assertEquals("Sube", SuplementacionPestana.etiquetaEstado("sube"))
        assertEquals("Baja", SuplementacionPestana.etiquetaEstado("baja"))
        assertEquals("Vuelve", SuplementacionPestana.etiquetaEstado("vuelve"))
        assertNull(SuplementacionPestana.etiquetaEstado("sigue"))
        assertNull(SuplementacionPestana.etiquetaEstado("sale"))
        assertNull(SuplementacionPestana.etiquetaEstado("otro"))
    }

    /**
     * Los días, con los vectores que iOS también corre (`apps/shared/vectores/texto_dias.json`): `dias` tal como llega en
     * el jsonb (texto, array con números o basura), leído como lo lee la app, y el texto que se muestra.
     */
    @Test
    fun diasConLosVectoresCompartidos() {
        val casos = Vectores.json(Vectores.publico("texto_dias"))["casos"]!!.jsonArray
        assertTrue(casos.size >= 15)
        for (c in casos) {
            val o = c.jsonObject
            val item = sup("""{"items":[{"nombre":"X","momento":"cena","dias":${o["dias"]}}]}""").items[0]
            val esperado = (o["texto"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
            assertEquals(esperado, SuplementacionPestana.textoDias(item.dias), "dias = ${o["dias"]}")
        }
    }

    @Test
    fun diasSueltos() {
        assertNull(SuplementacionPestana.textoDias(emptyList()))
        assertEquals("Días de entreno y sábado", SuplementacionPestana.textoDias(listOf("gym", "sábado")))
        assertEquals("Lunes, miércoles y viernes", SuplementacionPestana.textoDias(listOf("lun", "MIE", "viernes")))
        assertEquals("Feriados", SuplementacionPestana.textoDias(listOf("feriados")))
    }

    @Test
    fun detalleDeUnItem() {
        val creatina = SuplementacionPestana.detalle(demo.items[0], demo)
        assertEquals("Nuevo", creatina.etiqueta)
        assertEquals("5 g", creatina.dosis)
        assertEquals("5 g", creatina.dosisHablada)
        assertEquals(listOf(SuplementacionPestana.Toma("Con el desayuno", null, null)), creatina.tomas)
        assertEquals(2, creatina.detalle.size)
        assertEquals(CompraSuplemento("Creatina monohidrato 100 % pura", null, null), creatina.comprar)

        val omega = SuplementacionPestana.detalle(demo.items[1], demo)
        assertEquals("Sigue igual", omega.etiqueta)
        // Sin `cantidad` arriba (va en cada toma), como iOS.
        assertNull(omega.dosis)
        assertEquals(
            listOf(SuplementacionPestana.Toma("Con el desayuno", "1 g", null), SuplementacionPestana.Toma("30 minutos antes de acostarte", "1 g", null)),
            omega.tomas,
        )

        val cafeina = SuplementacionPestana.detalle(demo.items[2], demo)
        assertTrue(cafeina.opcional)
        assertEquals("Días de entreno", cafeina.dias)
        assertEquals("No después de las 17", cafeina.nota)

        val magnesio = SuplementacionPestana.detalle(demo.items[3], demo)
        assertEquals("Sube", magnesio.etiqueta)
        // «antes → ahora», como iOS.
        assertEquals("200 mg → 400 mg", magnesio.dosis)
        assertEquals("Antes 200 mg, ahora 400 mg", magnesio.dosisHablada)

        val multi = SuplementacionPestana.detalle(demo.items[4], demo)
        assertTrue(multi.sale)
        assertNull(multi.etiqueta)
        assertTrue(multi.tomas.isEmpty())
        assertEquals("Ya lo cubrís con la dieta", multi.porQue)
        assertNull(multi.dosis)
        assertFalse(creatina.sale)
    }

    @Test
    fun dosisComoIOS() {
        val s = sup(
            """{"items":[
                {"nombre":"A","cantidad":"5 g","antes":"5 g"},
                {"nombre":"B","cantidad":"5 g","antes":""},
                {"nombre":"C","antes":"3 g"},
                {"nombre":"D","cantidad":"2 cápsulas","antes":"1 cápsula","estado":"sale"}
            ]}""",
        )
        assertEquals(listOf("5 g", "5 g", null, "1 cápsula → 2 cápsulas"), s.items.map { SuplementacionPestana.dosis(it) })
        // El que sale no muestra dosis en el detalle.
        assertNull(SuplementacionPestana.detalle(s.items[3], s).dosis)
    }

    /** El detalle abierto se busca por su lugar y se confirma por el nombre: si un refresco puso otro ahí, se cierra. */
    @Test
    fun detalleAbiertoPorLugarYNombre() {
        val antes = demo.items
        assertEquals("Omega 3", SuplementacionPestana.itemAbierto(antes, 1, "Omega 3")?.nombre)
        assertNull(SuplementacionPestana.itemAbierto(antes, null, null))
        // Después de un refresco que sacó la creatina, en el lugar 1 quedó otro: se cierra.
        val despues = antes.drop(1)
        assertNull(SuplementacionPestana.itemAbierto(despues, 1, "Omega 3"))
        // La lista se achicó y el lugar ya no existe: también.
        assertNull(SuplementacionPestana.itemAbierto(despues.take(1), 3, "Magnesio glicinato"))
        // El mismo nombre en el mismo lugar (con la dosis cambiada): sigue abierto, con lo nuevo.
        val cambiada = antes.mapIndexed { i, it -> if (i == 3) it.copy(cantidad = "600 mg") else it }
        assertEquals("600 mg", SuplementacionPestana.itemAbierto(cambiada, 3, "Magnesio glicinato")?.cantidad)
    }

    @Test
    fun loQueLeeTalkBack() {
        val v = SuplementacionVista.armar(demo)
        assertEquals("Cafeína, 200 mg, Nuevo, Opcional, Días de entreno, No después de las 17", SuplementacionPestana.descripcionFila(v.momentos[1].filas[0]))
        assertEquals("Omega 3, 1 g", SuplementacionPestana.descripcionFila(v.momentos[0].filas[1]))
    }
}
