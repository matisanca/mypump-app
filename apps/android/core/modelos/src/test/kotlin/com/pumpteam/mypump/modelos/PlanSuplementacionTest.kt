package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La pestaña Suplementación: una fila de `mypump_suplementacion` (contrato, sección 10; los datos son ficticios). */
class PlanSuplementacionTest {
    /** El ejemplo del contrato (`docs/NATIVA_CONTRATO.md`, sección 10), tal cual. */
    private val ejemplo = """
        {
          "suplementacion": {
            "titulo": "Tu suplementación",
            "accion": "Empezá esta semana con lo nuevo",
            "dia": [
              { "id": "desayuno", "nombre": "Con el desayuno" },
              { "id": "pre", "nombre": "30 a 60 minutos antes de entrenar" },
              { "id": "dormir", "nombre": "30 minutos antes de acostarte" }
            ],
            "items": [
              { "nombre": "Creatina monohidrato", "cantidad": "5 g", "momento": "desayuno", "estado": "nuevo",
                "detalle": ["Todos los días, también los de descanso", "Con agua o con el desayuno"],
                "por_que": "Te ayuda a rendir más en las series pesadas",
                "comprar": { "buscar": "Creatina monohidrato 100 % pura" }, "video_id": "VID-1" },
              { "nombre": "Omega 3", "estado": "sigue",
                "tomas": [ { "momento": "desayuno", "cantidad": "1 g" }, { "momento": "dormir", "cantidad": "1 g" } ] },
              { "nombre": "Cafeína", "cantidad": "200 mg", "momento": "pre", "estado": "nuevo", "dias": "gym", "opcional": true,
                "nota": "No después de las 17" },
              { "nombre": "Magnesio glicinato", "cantidad": "400 mg", "antes": "200 mg", "momento": "dormir", "estado": "sube" },
              { "nombre": "Multivitamínico", "estado": "sale", "por_que": "Ya lo cubrís con la dieta" }
            ]
          },
          "fase": "final",
          "actualizado": "2026-11-04T18:30:00+00:00",
          "esquema": 1
        }
    """.trimIndent()

    private fun leer(t: String) = PlanSuplementacion.desde(Json.parseToJsonElement(t))

    @Test
    fun elEjemploDelContrato() {
        val p = leer(ejemplo)!!
        assertEquals("final", p.fase)
        assertEquals("2026-11-04T18:30:00+00:00", p.actualizado)
        assertEquals(1, p.esquema)
        val s = p.suplementacion
        assertEquals("Tu suplementación", s.titulo)
        assertEquals("Empezá esta semana con lo nuevo", s.accion)
        assertNull(s.sigueTexto)
        assertEquals(listOf("desayuno", "pre", "dormir"), s.dia.map { it.id })
        assertEquals("Con el desayuno", s.dia[0].nombre)
        assertEquals(5, s.items.size)

        val creatina = s.items[0]
        assertEquals("5 g", creatina.cantidad)
        assertEquals("desayuno", creatina.momento)
        assertEquals(listOf("Todos los días, también los de descanso", "Con agua o con el desayuno"), creatina.detalle)
        assertEquals("Te ayuda a rendir más en las series pesadas", creatina.porQue)
        assertEquals(CompraSuplemento("Creatina monohidrato 100 % pura", null, null), creatina.comprar)
        assertEquals("VID-1", creatina.videoId)
        assertTrue(creatina.dias.isEmpty())

        val omega = s.items[1]
        assertNull(omega.momento)
        assertEquals(listOf("desayuno", "dormir"), omega.tomas.map { it.momento })
        assertEquals(listOf("1 g", "1 g"), omega.tomas.map { it.cantidad })

        val cafeina = s.items[2]
        assertEquals(listOf("gym"), cafeina.dias)
        assertTrue(cafeina.opcional)
        assertEquals("No después de las 17", cafeina.nota)

        val magnesio = s.items[3]
        assertEquals("sube", magnesio.estado)
        assertEquals("200 mg", magnesio.antes)

        val multi = s.items[4]
        assertEquals("sale", multi.estado)
        assertNull(multi.momento)
        assertTrue(multi.tomas.isEmpty())
        assertEquals("Ya lo cubrís con la dieta", multi.porQue)
    }

    @Test
    fun laMuestraDeLaDemoSeLee() {
        val p = leer(Rutas.leer(Rutas.compartido("demo/suplementacion.json")))
        assertNotNull(p)
        assertEquals(5, p!!.suplementacion.items.size)
    }

    @Test
    fun detalleTextoOLista() {
        fun item(detalle: String) = leer("""{"suplementacion":{"items":[{"nombre":"X","momento":"cena","detalle":$detalle}]}}""")!!.suplementacion.items[0]
        assertEquals(listOf("Con comida"), item("\"Con comida\"").detalle)
        assertEquals(listOf("Uno", "Dos"), item("""["Uno", "", "Dos"]""").detalle)
        assertTrue(item("\"  \"").detalle.isEmpty())
        assertTrue(item("null").detalle.isEmpty())
    }

    @Test
    fun diasTextoOListaYComprarCompleto() {
        val s = leer(
            """{"suplementacion":{"items":[
                {"nombre":"A","momento":"cena","dias":["lunes","jueves"],"cambio":"de 3 a 5 g",
                 "comprar":{"buscar":"Zinc","donde":"Farmacia","nota":"Sin hierro"}},
                {"nombre":"B","momento":"cena","dias":"descanso"},
                {"nombre":"C","momento":"cena","dias":"todos","comprar":{}}
            ]}}""",
        )!!.suplementacion
        assertEquals(listOf("lunes", "jueves"), s.items[0].dias)
        assertEquals("de 3 a 5 g", s.items[0].cambio)
        assertEquals(CompraSuplemento("Zinc", "Farmacia", "Sin hierro"), s.items[0].comprar)
        assertEquals(listOf("descanso"), s.items[1].dias)
        assertEquals(listOf("todos"), s.items[2].dias)
        assertNull(s.items[2].comprar)
    }

    @Test
    fun momentoDesconocidoNoRompe() {
        val s = leer("""{"suplementacion":{"dia":[{"id":"siesta","nombre":"Después de la siesta"}],"items":[{"nombre":"A","momento":"siesta"}]}}""")!!.suplementacion
        assertEquals("siesta", s.items[0].momento)
        assertEquals("Después de la siesta", s.dia[0].nombre)
        assertNull(s.items[0].estado)
    }

    @Test
    fun esquemaDosConCamposNuevos() {
        val p = leer(
            """{"suplementacion":{"version_nueva":{"x":1},"dia":[],"items":[
                {"nombre":"A","momento":"cena","estado":"nuevo","color":"#fff","tomas_v2":[1,2],"comprar":{"buscar":"A","link":"x"}}
            ],"extra":[1]},"fase":"pre","esquema":2,"otro":true}""",
        )!!
        assertEquals(2, p.esquema)
        assertEquals("pre", p.fase)
        assertNull(p.actualizado)
        assertEquals("A", p.suplementacion.items[0].nombre)
        assertEquals(CompraSuplemento("A", null, null), p.suplementacion.items[0].comprar)
        // La caché guarda el JSON tal cual: los campos nuevos no se pierden y se vuelve a leer igual.
        val vuelta = PlanSuplementacion.desde(p.aValor())
        assertEquals(p, vuelta)
        assertTrue(p.aValor().aJson().toString().contains("version_nueva"))
    }

    @Test
    fun sinItemsOFormaRota() {
        assertNull(leer("""{"suplementacion":{"items":[]}}"""))
        assertNull(leer("""{"suplementacion":{"items":[{"cantidad":"5 g"}]}}"""))
        assertNull(leer("""{"suplementacion":"texto"}"""))
        assertNull(leer("[]"))
        assertNull(PlanSuplementacion.desde(null as ValorJson?))
        // Sin esquema (o uno inválido): 1.
        assertEquals(1, leer("""{"suplementacion":{"items":[{"nombre":"A"}]},"esquema":0}""")!!.esquema)
        assertFalse(leer("""{"suplementacion":{"items":[{"nombre":"A"}]}}""")!!.suplementacion.items[0].opcional)
    }
}
