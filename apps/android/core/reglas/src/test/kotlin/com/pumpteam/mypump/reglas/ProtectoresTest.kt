package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Suplementacion
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los protectores van aparte de «Tu día» (vectores `protectores.json`, iguales en la web e iOS). */
class ProtectoresTest {
    private val v = Vectores.json(Vectores.publico("protectores"))
    private fun txt(e: kotlinx.serialization.json.JsonElement?): String? = if (e == null || e is JsonNull) null else e.jsonPrimitive.content
    private fun momentos(vista: SuplementacionVista.Vista) = vista.momentos.map { it.id to it.filas.map { f -> f.nombre } }
    private fun esperados(a: JsonArray) = a.map { val o = it.jsonObject; txt(o["id"])!! to o["nombres"]!!.jsonArray.map { n -> txt(n)!! } }

    @Test fun losProtectoresVanAparte() {
        val vista = SuplementacionVista.armar(Suplementacion.desde(v["suplementacion"])!!)
        assertEquals(txt(v["titulo"]), SuplementacionVista.TITULO_PROTECTORES)
        // El id del grupo sin momento es propio de cada plataforma: se compara por título.
        assertEquals(esperados(v["momentos"]!!.jsonArray), momentos(vista))
        val esp = v["protectores"]!!.jsonArray.map { val o = it.jsonObject; listOf(txt(o["nombre"]), txt(o["cantidad"]), txt(o["momento"]), txt(o["nota"]), txt(o["item"])) }
        assertEquals(esp, vista.protectores.map { listOf(it.nombre, it.cantidad, it.momento, it.nota, it.indice.toString()) })
        assertEquals(v["sale"]!!.jsonArray.map { txt(it) }, vista.sale.map { it.nombre })
    }

    @Test fun sinElCampoLaVistaQuedaComoAntes() {
        val s = v["suplementacion"]!!.jsonObject
        val items = JsonArray(s["items"]!!.jsonArray.map { JsonObject(it.jsonObject - "protector" - "tipo") })
        val vista = SuplementacionVista.armar(Suplementacion.desde(JsonObject(s + ("items" to items)))!!)
        assertTrue(vista.protectores.isEmpty())
        val esp = esperados(v["sinCampo"]!!.jsonObject["momentos"]!!.jsonArray).map { if (it.first == "_ademas") "__ademas__" to it.second else it }
        assertEquals(esp, momentos(vista))
    }
}
