package com.pumpteam.mypump.datos

import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/**
 * GEN-05 (AvisoPlanIncompletoTests de iOS): el aviso "a tu plan le falta información", como la web
 * (`avisarPlanIncompleto`, cliente.html:8779-8798): lo de la rutina primero y, de una dieta que no sirve, solo "está
 * incompleta". A propósito, a quien tiene rutina y no dieta no se le avisa.
 */
class AvisoPlanIncompletoTest {
    private fun comida(id: String, nombre: String, kcal: Int) =
        """{"id":"$id","name":"$nombre","options":[{"name":"A","foods":[{"name":"Arroz","qty":100,"unit":"g","kcal":$kcal,"prot":10,"carb":20,"fat":5}]}]}"""

    private val rutinaSinSemanas = """[{"id":"rut-1","version":1,"semana_actual":1,"estructura":{"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]},{"id":"d2","nombre":"Día 2","bloques":[]}]}}]"""
    private val dietaSinObjetivo = """[{"id":"33333333-3333-4333-8333-333333333333","version":1,"estructura":{"comidas":[""" +
        comida("c1", "Desayuno", 400) + "]}}]"
    private val rutinaCompleta = """[{"id":"rut-2","version":1,"semana_actual":1,"estructura":{"semanas_total":12,"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}]"""
    private val dietaInservible = """[{"id":"44444444-4444-4444-8444-444444444444","version":1,"estructura":{"comidas":[{"id":"c1","name":"Desayuno","options":[]}]}}]"""

    private fun modelo(rutina: String, dieta: String, alcance: CoroutineScope): ModeloApp {
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_rutina_activa" -> 200 to rutina
                "mypump_get_dieta_activa" -> 200 to dieta
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("aviso-plan"), PreferenciasEnMemoria(), alcance)
    }

    @Test
    fun primeroLoDeLaRutinaYDespuesLoDeLaDieta() = enUnHilo { alcance ->
        val m = modelo(rutinaSinSemanas, dietaSinObjetivo, alcance)
        m.cargar()
        val aviso = m.avisoPlanIncompleto
        assertNotNull(aviso)
        assertEquals("A tu plan le falta información y algunas cosas pueden verse raras. Avisale a Mati y lo republica.", aviso!!.first)
        assertEquals(
            "Día 2: sin ejercicios. · El plan no dice cuántas semanas dura; se asume 12. · El plan no traía el objetivo de calorías; se calculó con la opción A.",
            aviso.second,
        )
    }

    @Test
    fun unaDietaQueNoSirveDiceQueEstaIncompleta() = enUnHilo { alcance ->
        val m = modelo("[]", dietaInservible, alcance)
        m.cargar()
        assertEquals("Tu dieta está publicada pero incompleta.", m.avisoPlanIncompleto?.second)
    }

    @Test
    fun conRutinaYSinDietaNoHayAviso() = enUnHilo { alcance ->
        val m = modelo(rutinaCompleta, "[]", alcance)
        m.cargar()
        assertNull(m.avisoPlanIncompleto, "a quien solo tiene rutina no se le deja un aviso de error fijo")
    }
}
