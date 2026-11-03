package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Macros
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Lo que agrega ModeloApp sobre las reglas: la dieta normalizada como la web y el aviso de plan incompleto (GEN-05). */
class ModeloAppTest {
    private val info = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""

    // Una opción vacía en el medio, una comida sin opciones y sin macros_target.
    private val dieta = """[{"id":"d1","version":1,"estructura":{"comidas":[
        {"id":"c1","name":"Desayuno","options":[
            {"name":"A","foods":[{"name":"Avena","qty":50,"unit":"g","kcal":190,"prot":6.5,"carb":33,"fat":3.5}]},
            {"name":"B","foods":[]},
            {"name":"C","foods":[{"name":"Yogur","qty":200,"unit":"g","kcal":120,"prot":10,"carb":14,"fat":3}]}]},
        {"id":"c2","name":"Merienda","options":[{"name":"A","foods":[]}]},
        {"id":"c3","name":"Cena","options":[{"name":"A","foods":[{"name":"Pollo","qty":150,"unit":"g","kcal":247.5,"prot":46.5,"carb":0,"fat":5.4}]}]}
    ]}}]"""

    @Test
    fun laDietaLlegaNormalizadaYAvisaLoQueFalta() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_dieta_activa" -> 200 to dieta
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("tokenDePrueba_0000000000"), carpetaTemporal("normalizar"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(listOf("c1", "c3"), m.comidasDelDia.map { it.id })
        // La opción C pasa a ser la segunda: los swaps se guardan con ese índice, como en la web.
        assertEquals(listOf("A", "C"), m.comidasDelDia[0].opciones.map { it.nombre })
        // Sin macros_target: la suma de la opción A, redondeada como Math.round.
        assertEquals(Macros(kcal = 438.0, prot = 53.0, carb = 33.0, fat = 9.0), m.objetivo)
        assertEquals(
            listOf("Merienda: sin opciones cargadas.", "El plan no traía el objetivo de calorías; se calculó con la opción A."),
            m.problemasDieta.value,
        )
        val aviso = m.avisoPlanIncompleto
        assertTrue(aviso!!.second.startsWith("Merienda: sin opciones cargadas."))
    }

    @Test
    fun unaDietaSinNingunaComidaUsableEsQueNoHayPlan() = enUnHilo { alcance ->
        val vacia = """[{"id":"d1","version":1,"estructura":{"comidas":[{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[]}]}]}}]"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_dieta_activa" -> 200 to vacia
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("tokenDePrueba_0000000000"), carpetaTemporal("normalizar"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertNull(m.dieta.value)
        assertTrue(m.problemasDieta.value.isNotEmpty())
    }
}
