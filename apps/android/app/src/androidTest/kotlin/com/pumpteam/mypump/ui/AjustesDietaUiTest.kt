package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlin.math.abs
import com.pumpteam.mypump.reglas.FechaLocal
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

        // D25: la había marcado «Comí»; al decir que hoy no la come, la marca se va.
        p.tocar(etiqueta("comi-c1"))
        p.esperar("marcada en el servidor") { servidor.marcasGuardadas()["${FechaLocal.hoy()}|c1"] != null }
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
        // Ni «Comí» ni «Salté»: no suma ni cuenta entre las comidas del día.
        assertFalse(p.existe(etiqueta("comi-c1")))
        assertFalse(p.existe(etiqueta("salte-c1")))
        p.esperar("la marca se borró") { servidor.marcasGuardadas().isEmpty() && servidor.a("mypump_desmarcar_comida").isNotEmpty() }
        assertEquals("0 de 2.373 kcal", p.estado(etiqueta("consumido-kcal")))
        val almuerzo = p.textosBajo(etiqueta("ajuste-aviso-c2"))
        assertTrue(almuerzo.toString(), almuerzo.any { it.startsWith("+") && it.endsWith("kcal por el Desayuno") })
        assertTrue(ultimoGuardado().getJSONObject("p_ajustes").getJSONObject("c1").getBoolean("omitida"))
    }

    /** El ajuste del desayuno que salió por la cola (sin esperar: se lee adentro de `p.esperar`). */
    private fun ajusteDelDesayuno(): JSONObject? =
        servidor.a("mypump_guardar_ajustes_dieta").lastOrNull()?.let { JSONObject(it).getJSONObject("p_ajustes").optJSONObject("c1") }

    /**
     * D25: con «Comí», mirar otra opción no toca el ajuste ni lo comido. Antes el ajuste se pasaba a la opción que se miraba
     * y se descartaban las cantidades a mano (revisión del 27-oct).
     */
    @Test
    fun conComiMirarOtraOpcionNoTocaElAjusteNiLoComido() {
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.tocar(etiqueta("ajuste-mas"))
        p.tocar(etiqueta("ajuste-mas"))
        p.tocar(etiqueta("ajuste-listo"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.esperar("el ajuste en el servidor") { ajusteDelDesayuno()?.optInt("deltaKcal") == 100 }
        p.tocar(etiqueta("comi-c1"))
        p.esperar("marcada en el servidor") { servidor.marcasGuardadas()["${FechaLocal.hoy()}|c1"] != null }
        val comido = p.estado(etiqueta("consumido-kcal"))
        assertTrue(comido, comido != "0 de 2.373 kcal")
        val guardados = servidor.a("mypump_guardar_ajustes_dieta").size
        p.tocar(etiqueta("opcion-c1-1"))
        p.esperar("mira la B") { p.seleccionado(etiqueta("opcion-c1-1")) }
        p.quieto(1_000)
        assertEquals("mirar no guarda otro ajuste", guardados, servidor.a("mypump_guardar_ajustes_dieta").size)
        assertEquals("el ajuste sigue en la A", 0, ajusteDelDesayuno()!!.optInt("opcion", 0))
        assertEquals(comido, p.estado(etiqueta("consumido-kcal")))
        assertTrue(p.seleccionado(etiqueta("comi-c1")))
    }

    // ── 2.0.3: agregar un alimento a la comida (D1) y tocar la cantidad en la fila (D2) ──

    /** Las kcal de la hoja de cantidad: «21 kcal». */
    private fun kcalCantidad(): Int = p.textosBajo(etiqueta("cantidad-kcal")).first().filter(Char::isDigit).toInt()

    private fun campoCantidad(): String? = p.textosBajo(etiqueta("cantidad-campo")).firstOrNull { it.firstOrNull()?.isDigit() == true }

    /**
     * D1 (el pedido: «comí 80 g de puré de zapallo y no lo pude cargar»): se busca en la base, se eligen los gramos con las
     * kcal en vivo y queda en la misma comida, que sube y lo dice; sale por la cola dentro del ajuste (y en el resumen); el
     * «+» de los recientes lo suma de un toque; sobrevive a reabrir; con «Comí» tiene su tilde; se saca desde su hoja y
     * «Volver al plan» saca todo. Gemela de testAgregarUnAlimentoALaComidaConSusGramos de iOS.
     */
    @Test
    fun agregarUnAlimentoALaComidaConSusGramos() {
        guardarCuenta()
        abrir().also {
            irADieta()
            p.tocar(etiqueta("agregar-c1"))
            p.nodo(etiqueta("hoja-agregar"))
            p.escribir(etiqueta("buscar-agregar"), "zapallo")
            p.nodo(texto("Zapallo / Calabaza"))
            Telefono.captura("60-agregar-busqueda-claro")
            p.tocar(texto("Zapallo / Calabaza"))
            p.nodo(etiqueta("cantidad-campo"))
            assertEquals("100", campoCantidad())
            assertEquals(26, kcalCantidad())
            repeat(4) { p.tocar(etiqueta("cantidad-menos")) }
            p.esperar("80 g") { campoCantidad() == "80" }
            assertEquals("las kcal en vivo", 21, kcalCantidad())
            assertTrue("la medida casera", p.existe(etiqueta("cantidad-medida-1")))
            assertTrue(p.prendido(etiqueta("cantidad-compensar")))
            Telefono.captura("61-agregar-cantidad-claro")
            assertEquals(listOf("Agregar al Desayuno"), p.textosBajo(etiqueta("cantidad-confirmar")))
            p.tocar(etiqueta("cantidad-confirmar"))
            p.esperarQueNoEste(etiqueta("hoja-agregar"))

            p.nodo(etiqueta("agregado-c1-0"))
            assertEquals(listOf("Cantidad de Zapallo / Calabaza: 80 g"), p.textosBajo(etiqueta("agregado-c1-0")))
            p.esperar("el aviso del desayuno") { p.textosBajo(etiqueta("ajuste-aviso-c1")).any { it.startsWith("Ajustada: +21 kcal") } }
            assertTrue(p.textosBajo(etiqueta("resumen-c1")).single().endsWith(" + 1 agregado"))
            val g = ultimoGuardado()
            val ag = g.getJSONObject("p_ajustes").getJSONObject("c1").getJSONArray("agregados")
            assertEquals(1, ag.length())
            assertEquals("Zapallo / Calabaza", ag.getJSONObject(0).getString("nombre"))
            assertEquals(80.0, ag.getJSONObject(0).getDouble("gramos"), 0.01)
            assertEquals("base", ag.getJSONObject(0).getString("origen"))
            val fila = (0 until g.getJSONArray("p_resumen").length()).map { g.getJSONArray("p_resumen").getJSONObject(it) }.first { it.optString("comida_id") == "c1" }
            assertEquals(1, fila.getJSONArray("agregados").length())
            Telefono.captura("62-agregado-en-la-comida-claro")

            // El «+» de los recientes: el mismo, de un toque.
            p.tocar(etiqueta("agregar-c1"))
            p.nodo(etiqueta("hoja-agregar"))
            p.tocar(etiqueta("reciente-agregar-0"))
            p.esperarQueNoEste(etiqueta("hoja-agregar"))
            p.nodo(etiqueta("agregado-c1-1"))
            p.esperar("+42") { p.textosBajo(etiqueta("ajuste-aviso-c1")).any { it.startsWith("Ajustada: +42 kcal") } }
            p.esperar("los dos en el servidor") { ajusteDelDesayuno()?.optJSONArray("agregados")?.length() == 2 }
            Unit
        }.close()

        // Al abrir de nuevo siguen (quedaron en el teléfono).
        abrir()
        irADieta()
        p.nodo(etiqueta("agregado-c1-1"))
        // «Comí» los cuenta y tienen su tilde, después de los del plan.
        val n = p.textosBajo(etiqueta("resumen-c1")).single().substringAfter("· ").substringBefore(" ").toInt()
        val antes = p.estado(etiqueta("consumido-kcal"))
        p.tocar(etiqueta("comi-c1"))
        p.esperar("sumó el desayuno") { p.estado(etiqueta("consumido-kcal")) != antes }
        val conTodo = p.estado(etiqueta("consumido-kcal"))!!.substringBefore(" de").filter(Char::isDigit).toInt()
        assertTrue(p.prendido(etiqueta("comido-c1-${n + 1}")))
        p.tocar(etiqueta("comido-c1-${n + 1}"))
        p.esperar("destildado") { !p.prendido(etiqueta("comido-c1-${n + 1}")) }
        val sinEse = p.estado(etiqueta("consumido-kcal"))!!.substringBefore(" de").filter(Char::isDigit).toInt()
        assertEquals("destildar el agregado descuenta sus kcal", conTodo - 21, sinEse)
        p.tocar(etiqueta("comi-c1"))
        p.esperar("desmarcada") { !p.seleccionado(etiqueta("comi-c1")) }

        // Se saca desde su hoja.
        p.tocar(etiqueta("agregado-c1-1"))
        p.nodo(etiqueta("hoja-cantidad"))
        p.tocar(etiqueta("cantidad-borrar"))
        p.esperarQueNoEste(etiqueta("hoja-cantidad"))
        p.esperarQueNoEste(etiqueta("agregado-c1-1"))
        p.nodo(etiqueta("agregado-c1-0"))

        // «Volver al plan» también los saca.
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        p.nodo(etiqueta("ajuste-agregados"))
        p.tocar(etiqueta("ajuste-volver-plan"))
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.esperarQueNoEste(etiqueta("agregado-c1-0"))
        p.esperar("volvió al plan en el servidor") { ultimoGuardado().getJSONObject("p_ajustes").length() == 0 }
    }

    /**
     * D2: la cantidad de un alimento del plan se toca en la fila, se cambia con las kcal en vivo, queda a mano (la comida lo
     * dice y sale en `cantidades`) y «Como el plan» la devuelve. Gemela de testTocarLaCantidadDeUnAlimentoDelPlan de iOS.
     */
    @Test
    fun tocarLaCantidadDeUnAlimentoDelPlan() {
        guardarCuenta()
        abrir()
        irADieta()
        val antes = p.textosBajo(etiqueta("cantidad-c1-0")).single()
        p.tocar(etiqueta("cantidad-c1-0"))
        p.nodo(etiqueta("hoja-cantidad"))
        val kcal0 = kcalCantidad()
        p.tocar(etiqueta("cantidad-mas"))
        p.tocar(etiqueta("cantidad-mas"))
        p.esperar("las kcal suben en vivo") { kcalCantidad() > kcal0 }
        assertTrue(p.textosBajo(etiqueta("cantidad-lista")).any { it.startsWith("En el plan: ") })
        Telefono.captura("63-cantidad-del-plan-claro")
        assertEquals(listOf("Listo"), p.textosBajo(etiqueta("cantidad-confirmar")))
        p.tocar(etiqueta("cantidad-confirmar"))
        p.esperarQueNoEste(etiqueta("hoja-cantidad"))
        p.nodo(etiqueta("ajuste-aviso-c1"))
        p.esperar("la fila con la cantidad nueva") { p.textosBajo(etiqueta("cantidad-c1-0")).single() != antes }
        assertTrue(p.textosBajo(etiqueta("alimento-c1-0")).any { it.startsWith("En el plan: ") })
        p.esperar("a mano en el servidor") { ajusteDelDesayuno()?.optJSONObject("cantidades")?.has("0") == true }

        p.tocar(etiqueta("cantidad-c1-0"))
        p.nodo(etiqueta("hoja-cantidad"))
        p.tocar(etiqueta("cantidad-como-plan"))
        p.esperarQueNoEste(etiqueta("hoja-cantidad"))
        p.esperarQueNoEste(etiqueta("ajuste-aviso-c1"))
        assertEquals(antes, p.textosBajo(etiqueta("cantidad-c1-0")).single())
        p.esperar("como el plan en el servidor") { ultimoGuardado().getJSONObject("p_ajustes").length() == 0 }
    }

    /** Las pantallas nuevas en oscuro y «Salté» sin «Agregar alimento» (revisión del 3-nov). */
    @Test
    fun agregarEnOscuroYSalteOcultaAgregar() {
        Telefono.modoNoche(true)
        try {
            guardarCuenta()
            abrir()
            irADieta()
            p.tocar(etiqueta("agregar-c1"))
            p.nodo(etiqueta("hoja-agregar"))
            p.escribir(etiqueta("buscar-agregar"), "zapallo")
            p.nodo(texto("Zapallo / Calabaza"))
            Telefono.captura("64-agregar-busqueda-oscuro")
            p.tocar(texto("Zapallo / Calabaza"))
            p.nodo(etiqueta("cantidad-kcal"))
            Telefono.captura("65-agregar-cantidad-oscuro")
            p.tocar(etiqueta("cantidad-confirmar"))
            p.esperarQueNoEste(etiqueta("hoja-agregar"))
            p.nodo(etiqueta("agregado-c1-0"))
            Telefono.captura("66-agregado-en-la-comida-oscuro")
            p.tocar(etiqueta("agregado-c1-0"))
            p.nodo(etiqueta("hoja-cantidad"))
            Telefono.captura("67-agregado-cantidad-oscuro")
            p.tocar(etiqueta("cantidad-cancelar"))
            p.esperarQueNoEste(etiqueta("hoja-cantidad"))

            p.tocar(etiqueta("salte-c1"))
            p.esperar("salteada") { p.seleccionado(etiqueta("salte-c1")) }
            p.esperarQueNoEste(etiqueta("agregar-c1"))
            p.tocar(etiqueta("salte-c1"))
            p.esperar("desmarcada") { !p.seleccionado(etiqueta("salte-c1")) }
            p.nodo(etiqueta("agregar-c1"))
        } finally {
            Telefono.modoNoche(false)
        }
    }
}
