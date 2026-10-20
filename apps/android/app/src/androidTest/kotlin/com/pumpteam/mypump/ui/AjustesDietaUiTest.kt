package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.math.abs
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Los ajustes de porciones del día (feedback del 20-oct) en el emulador, con la cuenta grabada (Desayuno, Almuerzo,
 * Merienda y Cena): sumar kcal y que compense la siguiente, que se guarde y siga al reabrir, «Volver al plan», «Hoy no la
 * como» y «Cancelar». Gemelas de testAjustarUnaComidaCompensaEnLaSiguienteYVuelveAlPlan y
 * testHoyNoLaComoPasaSusKcalALaSiguiente de iOS.
 */
@RunWith(AndroidJUnit4::class)
class AjustesDietaUiTest : PruebaUi() {
    private fun irADieta() {
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("dieta-cabecera"))
    }

    /** Las kcal de la hoja: «Kcal de esta comida: 644, +100 contra el plan…». */
    private fun kcalHoja(): Int =
        p.textosBajo(etiqueta("ajuste-kcal")).first().substringAfter(": ").substringBefore(",").filter(Char::isDigit).toInt()

    private fun ultimoGuardado(): JSONObject = JSONObject(p.esperar("se guardaron los ajustes") { servidor.a("mypump_guardar_ajustes_dieta").lastOrNull() })

    @Test
    fun sumarKcalCompensaEnLaSiguienteSeGuardaYVuelveAlPlan() {
        guardarCuenta()
        abrir().also {
            irADieta()
            assertEquals(listOf("Ajustar esta comida"), p.textosBajo(etiqueta("ajustar-c1")))
            p.tocar(etiqueta("ajustar-c1"))
            p.nodo(etiqueta("hoja-ajuste"))
            val antes = kcalHoja()
            assertEquals(544, antes)
            p.tocar(etiqueta("ajuste-mas"))
            p.tocar(etiqueta("ajuste-mas"))
            p.esperar("+100 kcal") { abs(kcalHoja() - antes - 100) <= 25 }
            assertEquals(listOf("+100 kcal"), p.textosBajo(etiqueta("ajuste-delta")))
            val efecto = p.textosBajo(etiqueta("ajuste-compensar-detalle")).single()
            assertTrue(efecto, efecto.startsWith("El Almuerzo baja "))
            assertTrue(p.prendido(etiqueta("ajuste-compensar")))
            // Las macros de la comida con lo que se apartan del plan (lo que pidió Emilio).
            val macros = p.textosBajo(etiqueta("ajuste-macros"))
            for (m in listOf("Proteínas: ", "Carbohidratos: ", "Grasas: ")) assertTrue(macros.toString(), macros.any { it.startsWith(m) && it.contains("más") })
            assertTrue(p.textosBajo(etiqueta("ajuste-dia")).single().startsWith("Tu día: "))
            Telefono.captura("30-ajuste-hoja-claro")
            p.tocar(etiqueta("ajuste-listo"))
            p.esperarQueNoEste(etiqueta("hoja-ajuste"))

            p.esperar("el aviso del desayuno") { p.textosBajo(etiqueta("ajuste-aviso-c1")).any { it.startsWith("Ajustada: +") } }
            assertEquals(listOf("Cambiar el ajuste"), p.textosBajo(etiqueta("ajustar-c1")))
            val almuerzo = p.textosBajo(etiqueta("ajuste-aviso-c2"))
            assertTrue(almuerzo.toString(), almuerzo.any { it.startsWith("−") && it.endsWith("kcal por el Desayuno") })
            assertEquals(listOf("Ajustar esta comida"), p.textosBajo(etiqueta("ajustar-c2")))
            p.nodo(textoQueContiene("Con tus ajustes de hoy: "))
            // Salió por la cola con el día entero.
            val g = ultimoGuardado()
            assertEquals(100, g.getJSONObject("p_ajustes").getJSONObject("c1").getInt("deltaKcal"))
            assertEquals(4, g.getJSONArray("p_resumen").length())
            Telefono.captura("31-ajuste-tarjetas-claro")
        }.close()

        // Al abrir de nuevo sigue (quedó en el teléfono) y «Volver al plan» lo saca.
        abrir()
        irADieta()
        p.nodo(etiqueta("ajuste-aviso-c1"))
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.tocar(etiqueta("ajuste-volver-plan"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.esperarQueNoEste(etiqueta("ajuste-aviso-c1"))
        assertFalse(p.existe(etiqueta("ajuste-aviso-c2")))
        p.esperar("volvió al plan en el servidor") { ultimoGuardado().getJSONObject("p_ajustes").length() == 0 }
    }

    /** Las capturas en oscuro (la evidencia de que la hoja y los avisos se leen con el tema del sistema). */
    @Test
    fun capturasEnOscuro() {
        Telefono.modoNoche(true)
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.tocar(etiqueta("ajuste-mas"))
        p.tocar(etiqueta("ajuste-mas"))
        p.esperar("+100 kcal") { p.textosBajo(etiqueta("ajuste-delta")) == listOf("+100 kcal") }
        Telefono.captura("33-ajuste-hoja-oscuro")
        p.tocar(etiqueta("ajuste-listo"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.nodo(etiqueta("ajuste-aviso-c1"))
        Telefono.captura("34-ajuste-tarjetas-oscuro")
        Telefono.modoNoche(false)
    }

    @Test
    fun hoyNoLaComoPasaSusKcalYCancelarNoGuarda() {
        guardarCuenta()
        abrir()
        irADieta()
        // Cancelar no guarda nada.
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.tocar(etiqueta("ajuste-mas"))
        p.tocar(etiqueta("ajuste-cancelar"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        assertFalse(p.existe(etiqueta("ajuste-aviso-c1")))

        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.tocar(etiqueta("ajuste-omitir"))
        p.esperar("prendido") { p.prendido(etiqueta("ajuste-omitir")) }
        assertFalse("sin comerla no se suman kcal", p.habilitado(etiqueta("ajuste-mas")))
        assertFalse("ni se tocan los alimentos", p.existe(etiqueta("ajuste-alimento-0")))
        assertTrue(p.textosBajo(etiqueta("ajuste-omitir-detalle")).single().startsWith("Sus 544 kcal pasan al Almuerzo"))
        Telefono.captura("32-ajuste-omitir-claro")
        p.tocar(etiqueta("ajuste-listo"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.esperar("el aviso") { p.textosBajo(etiqueta("ajuste-aviso-c1")).contains("Hoy no la comés") }
        assertFalse("sin los alimentos", p.existe(etiqueta("alimento-c1-0")))
        val almuerzo = p.textosBajo(etiqueta("ajuste-aviso-c2"))
        assertTrue(almuerzo.toString(), almuerzo.any { it.startsWith("+") && it.endsWith("kcal por el Desayuno") })
        assertTrue(ultimoGuardado().getJSONObject("p_ajustes").getJSONObject("c1").getBoolean("omitida"))
    }
}
