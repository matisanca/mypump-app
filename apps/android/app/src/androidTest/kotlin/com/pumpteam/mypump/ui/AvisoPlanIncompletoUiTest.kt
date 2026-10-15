package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

/**
 * GEN-05 en la pantalla: el aviso «a tu plan le falta información» arriba de Revisión, con los mismos tres casos que
 * `AvisoPlanIncompletoTests` de iOS (y `AvisoPlanIncompletoTest` del modelo), que siguen la regla de la web
 * (`avisarPlanIncompleto`):
 * - primero lo de la rutina y después lo de la dieta, los tres primeros, en un solo aviso;
 * - de una dieta que no sirve, solo «Tu dieta está publicada pero incompleta.»;
 * - a quien tiene rutina y no dieta no se le avisa nada (la web le dejaba un aviso de error fijo).
 *
 * No es para el cliente: es para la captura que le manda a Mati. Las respuestas son las del [ServidorDePrueba] con la
 * rutina y la dieta de cada caso.
 */
@RunWith(AndroidJUnit4::class)
class AvisoPlanIncompletoUiTest : PruebaUi() {
    private val aviso = etiqueta("aviso-plan-incompleto")

    /** La cuenta con esa rutina y esa dieta, sin sesión ni historial (la rutina no es la grabada). */
    private fun abrirConElPlan(rutina: String, dieta: String) {
        servidor.respuestas["mypump_get_rutina_activa"] = rutina
        servidor.respuestas["mypump_get_dieta_activa"] = dieta
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_get_historico_por_clave"] = "[]"
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-revision"))
    }

    private fun irARevision() {
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-midia"))
    }

    @Test
    fun primeroLoDeLaRutinaYDespuesLoDeLaDietaEnUnSoloAvisoArriba() {
        abrirConElPlan(RUTINA_SIN_SEMANAS, DIETA_SIN_OBJETIVO)
        irARevision()
        assertEquals(
            listOf(
                TEXTO,
                "Día 2: sin ejercicios. · El plan no dice cuántas semanas dura; se asume 12. · El plan no traía el objetivo de " +
                    "calorías; se calculó con la opción A.",
            ),
            p.textosBajo(aviso),
        )
        assertEquals("un solo aviso", 1, p.cuantos(aviso))
        // Arriba de todo: antes de las fotos, que son la primera tarjeta.
        p.esperar("el aviso va arriba de las fotos") {
            p.nodo(aviso, ms = 0).positionInRoot.y < p.nodo(etiqueta("seccion-fotos"), ms = 0).positionInRoot.y
        }
        Telefono.captura("revision-aviso-plan-incompleto-claro")
        // Es solo de Revisión: en las otras pestañas no está.
        p.tocar(etiqueta("pestana-entreno"))
        p.nodo(etiqueta("entreno-cabecera"))
        assertFalse(p.existe(aviso))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Desayuno"))
        assertFalse(p.existe(aviso))
    }

    @Test
    fun deUnaDietaQueNoSirveSoloDiceQueEstaIncompleta() {
        abrirConElPlan("[]", DIETA_INSERVIBLE)
        irARevision()
        assertEquals(listOf(TEXTO, "Tu dieta está publicada pero incompleta."), p.textosBajo(aviso))
    }

    @Test
    fun conRutinaYSinDietaNoHayAviso() {
        abrirConElPlan(RUTINA_COMPLETA, "[]")
        irARevision()
        // Que la carga haya terminado (Mi Día ya se puede tocar) antes de afirmar que no está.
        p.esperar("Mi Día cargado") { p.habilitado(texto("Dormí bien: sí")) }
        p.quieto(1_000)
        assertFalse("a quien solo tiene rutina no se le deja un aviso de error fijo: ${p.resumen()}", p.existe(aviso))
    }

    private companion object {
        const val TEXTO = "A tu plan le falta información y algunas cosas pueden verse raras. Avisale a Mati y lo republica."

        fun comida(id: String, nombre: String, kcal: Int) =
            """{"id":"$id","name":"$nombre","options":[{"name":"A","foods":[{"name":"Arroz","qty":100,"unit":"g","kcal":$kcal,"prot":10,"carb":20,"fat":5}]}]}"""

        // Las de AvisoPlanIncompletoTests de iOS.
        const val RUTINA_SIN_SEMANAS =
            """[{"id":"rut-1","version":1,"semana_actual":1,"estructura":{"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]},{"id":"d2","nombre":"Día 2","bloques":[]}]}}]"""
        val DIETA_SIN_OBJETIVO =
            """[{"id":"33333333-3333-4333-8333-333333333333","version":1,"estructura":{"comidas":[""" + comida("c1", "Desayuno", 400) + "]}}]"
        const val RUTINA_COMPLETA =
            """[{"id":"rut-2","version":1,"semana_actual":1,"estructura":{"semanas_total":12,"dias":[{"id":"d1","nombre":"Día 1","bloques":[{"ejercicios":[{"id":"e1","nombre":"Sentadilla","progresion":[{"semana":1,"series":3,"reps":"8"}]}]}]}]}}]"""
        const val DIETA_INSERVIBLE =
            """[{"id":"44444444-4444-4444-8444-444444444444","version":1,"estructura":{"comidas":[{"id":"c1","name":"Desayuno","options":[]}]}}]"""
    }
}
