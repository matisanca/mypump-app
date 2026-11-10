package com.pumpteam.mypump.ui

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.unit.toSize
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleFeedback
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.reglas.ReglasSupleEstado
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feedback del alumno contra el doble del servidor (sin red): «Me duele» desde el ejercicio y las marcas de «¿Ya lo tenés?» en
 * Suplementación. La decodificación y los reintentos están en `FeedbackModeloTest`. Gemelo de FeedbackUITests.swift.
 */
@RunWith(AndroidJUnit4::class)
class FeedbackUiTest : PruebaUi() {
    private val ejercicio = "jalon-al-pecho-prono-dorsal-ancho-d1-0"
    private var tema = "claro"

    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    /** Deja [a] al medio de la pantalla: lo nuevo queda abajo de lo que entra de entrada, y la captura no lo mostraba. */
    private fun aLaVista(a: String) {
        val n = p.nodo(etiqueta(a))
        p.enPrincipal {
            var lista = n.parent
            while (lista != null && lista.config.getOrNull(SemanticsActions.ScrollBy) == null) lista = lista.parent
            val l = lista ?: return@enPrincipal
            l.config[SemanticsActions.ScrollBy].action?.invoke(0f, Rect(n.positionInRoot, n.size.toSize()).center.y - l.boundsInRoot.center.y)
        }
        p.quieto(600)
    }

    private fun foto(nombre: String, a: String? = null) {
        if (a != null) aLaVista(a)
        Telefono.captura("android-$tema-$nombre")
    }

    /** El feedback y la palanca los contesta el doble; lo demás, el servidor de prueba de siempre. */
    private fun lanzar(escenario: String): DobleFeedback {
        val d = DobleFeedback.escenario(escenario, listOf(ejercicio))
        val s = servidor
        // La suplementación de la demo (ficticia) más un protector, que no se tiene que poder marcar.
        val fila = JSONObject(app.assets.open("demo/suplementacion.json").use { it.readBytes().toString(Charsets.UTF_8) })
        fila.getJSONObject("suplementacion").getJSONArray("items")
            .put(JSONObject().put("nombre", "Telmisartán").put("cantidad", "40 mg").put("momento", "desayuno").put("protector", true))
        s.respuestas["mypump_suplementacion"] = JSONArray().put(fila).toString()
        Entorno.transporte = Transporte { pedido -> if (DobleFeedback.esSuya(pedido.ruta.substringAfterLast('/'))) d.enviar(pedido) else s.enviar(pedido) }
        guardarCuenta()
        abrir()
        return d
    }

    private fun enElEjercicio(escenario: String): DobleFeedback {
        val d = lanzar(escenario)
        abrirPaginaDelEjercicio(ejercicio)
        return d
    }

    private fun enSuplementacion(escenario: String): DobleFeedback {
        val d = lanzar(escenario)
        p.tocar(etiqueta("pestana-suplementacion"))
        p.nodo(etiqueta("suplementacion-pantalla"))
        return d
    }

    private fun zona(): String = if (p.existe(etiqueta("duele-zona"))) p.textosBajo(etiqueta("duele-zona")).joinToString(" ") else ""

    private fun completarYEnviar(nivel: Int = 5, capturas: Boolean = false) {
        p.nodo(etiqueta("duele-dibujo"))
        assertFalse("Sin completar no se puede avisar", p.habilitado(etiqueta("duele-enviar")))
        p.nodo(etiqueta("duele-falta"))
        if (capturas) foto("duele-1-vacio")
        // Cada parte del dibujo se lee con su nombre.
        assertEquals("Hombro derecho", p.descripcion(etiqueta("duele-pieza-frente-hombro-derecho")))
        p.tocar(etiqueta("duele-pieza-frente-hombro-derecho"))
        p.esperar("la zona elegida") { zona() == "Hombro derecho" }
        assertTrue(p.seleccionado(etiqueta("duele-pieza-frente-hombro-derecho")))
        if (capturas) foto("duele-2-zona")
        p.tocar(etiqueta("duele-desde-esta_semana"))
        p.tocar(etiqueta("duele-cuando-al_subir"))
        p.tocar(etiqueta("duele-tipo-sordo"))
        p.tocar(etiqueta("duele-nivel-$nivel"))
        p.esperar("se puede avisar") { p.habilitado(etiqueta("duele-enviar")) }
        if (capturas) foto("duele-3-completo")
        p.tocar(etiqueta("duele-enviar"))
        p.nodo(etiqueta("duele-recibido"))
    }

    @Test fun avisarUnaMolestiaYCorregirla() {
        val d = enElEjercicio("vacio")
        foto("duele-0-ejercicio", "duele-abrir")
        p.tocar(etiqueta("duele-abrir"))
        completarYEnviar(capturas = true)
        p.nodo(texto("Ya me llegó"))
        p.nodo(texto("Lo veo y te ajusto el ejercicio."))
        assertFalse("Con «Bastante» no va la línea de dejar el ejercicio", p.existe(etiqueta("duele-listo-fuerte")))
        foto("duele-4-recibido")
        val j = d.ultimoRegistro!!
        assertEquals("android", j["p_plataforma"]?.comoTexto)
        assertEquals(ejercicio, j["p_ejercicio_id"]?.comoTexto)
        assertEquals("hombro", j["p_zona"]?.comoTexto)
        assertEquals("derecho", j["p_lado"]?.comoTexto)
        assertEquals(5.0, j["p_intensidad"]?.comoNumero)
        assertTrue("el día de la rutina", !j["p_dia_id"]?.comoTexto.isNullOrEmpty())
        assertTrue("la versión de la app", !j["p_version"]?.comoTexto.isNullOrEmpty())
        p.tocar(etiqueta("duele-listo"))
        p.esperarQueNoEste(etiqueta("hoja-me-duele"))
        // En la tarjeta queda avisada y el botón de la fila de acciones se va: se corrige desde ahí.
        p.nodo(etiqueta("duele-avisada"))
        assertFalse(p.existe(etiqueta("duele-abrir")))
        foto("duele-5-tarjeta", "duele-avisada")
        p.tocar(etiqueta("duele-cambiar"))
        p.esperar("Corregir abre con lo que ya avisó") { zona() == "Hombro derecho" }
        p.nodo(texto("Guardar cambios"))
        p.tocar(etiqueta("duele-vista-espalda"))
        p.tocar(etiqueta("duele-pieza-espalda-espalda_baja-centro"))
        p.esperar("la zona nueva") { zona() == "Espalda baja" }
        assertFalse("Una zona del centro no pregunta el lado", p.existe(etiqueta("duele-lado-ambos")))
        p.tocar(etiqueta("duele-nivel-9"))
        p.tocar(etiqueta("duele-enviar"))
        p.nodo(etiqueta("duele-recibido"))
        p.nodo(etiqueta("duele-listo-fuerte"))
        p.tocar(etiqueta("duele-listo"))
        p.esperarQueNoEste(etiqueta("hoja-me-duele"))
        p.nodo(etiqueta("duele-avisada"))
        p.nodo(texto("Espalda baja. Lo veo y te ajusto el ejercicio."))
        assertEquals("corregir no crea otra", 1, d.molestias.size)
        // «Me duele» no escribe comentarios.
        assertTrue(servidor.a("mypump_agregar_comentario").isEmpty())
    }

    @Test fun losDosLados() {
        enElEjercicio("vacio")
        p.tocar(etiqueta("duele-abrir"))
        p.tocar(etiqueta("duele-pieza-frente-rodilla-izquierdo"))
        p.esperar("rodilla izquierda") { zona() == "Rodilla izquierda" }
        p.tocar(etiqueta("duele-lado-ambos"))
        p.esperar("los dos lados") { zona() == "Rodilla, los dos lados" }
        // Con «los dos», tocar el otro lado en el dibujo no lo deshace.
        p.tocar(etiqueta("duele-pieza-frente-rodilla-derecho"))
        p.quieto(300)
        assertEquals("Rodilla, los dos lados", zona())
        assertTrue(p.seleccionado(etiqueta("duele-pieza-frente-rodilla-derecho")) && p.seleccionado(etiqueta("duele-pieza-frente-rodilla-izquierdo")))
    }

    @Test fun elDedoEnElDibujo() {
        enElEjercicio("vacio")
        p.tocar(etiqueta("duele-abrir"))
        p.nodo(etiqueta("duele-dibujo"))
        // Un toque de verdad, no la acción de accesibilidad: cae en la pieza por las cuentas de `FiguraCuerpo.pieza`.
        p.tocarDeVerdad(etiqueta("duele-pieza-frente-abdomen-centro"))
        p.esperar("abdomen") { zona() == "Abdomen" }
        p.tocarDeVerdad(etiqueta("duele-pieza-frente-codo-izquierdo"))
        p.esperar("codo") { zona() == "Codo izquierdo" }
    }

    @Test fun sinSenalSeDiceAhi() {
        val d = enElEjercicio("vacio")
        p.tocar(etiqueta("duele-abrir"))
        d.sinRed = true
        p.tocar(etiqueta("duele-pieza-frente-hombro-derecho"))
        p.tocar(etiqueta("duele-desde-hoy"))
        p.tocar(etiqueta("duele-cuando-al_bajar"))
        p.tocar(etiqueta("duele-tipo-punzante"))
        p.tocar(etiqueta("duele-nivel-2"))
        p.tocar(etiqueta("duele-enviar"))
        p.nodo(etiqueta("duele-fallo"))
        p.nodo(texto("No se pudo enviar. Revisá la conexión y probá de nuevo."))
        foto("duele-7-sin-senal")
        // El reintento sale con el mismo id: el servidor no duplica.
        d.sinRed = false
        p.tocar(etiqueta("duele-enviar"))
        p.nodo(etiqueta("duele-recibido"))
        assertEquals(1, d.molestias.size)
    }

    @Test fun sinPalanca() {
        val d = enElEjercicio("apagado")
        p.nodo(texto("Comentarios"))
        assertFalse("Con la palanca apagada no hay «Me duele»", p.existe(etiqueta("duele-abrir")))
        assertFalse(p.existe(etiqueta("duele-avisada")))
        assertTrue("ni se pregunta", d.llamadasFeedback.isEmpty())
    }

    @Test fun yaRevisada() {
        enElEjercicio("resuelta")
        p.nodo(etiqueta("duele-resuelta"))
        p.nodo(texto("Ya lo revisé"))
        assertTrue("Con la anterior cerrada puede avisar otra", p.existe(etiqueta("duele-abrir")))
        assertFalse(p.existe(etiqueta("duele-cambiar")))
        foto("duele-6-resuelta", "duele-resuelta")
    }

    @Test fun oscuro() {
        tema = "oscuro"
        Telefono.modoNoche(true)
        enElEjercicio("vacio")
        foto("duele-0-ejercicio", "duele-abrir")
        p.tocar(etiqueta("duele-abrir"))
        completarYEnviar(nivel = 7, capturas = true)
        p.nodo(etiqueta("duele-listo-fuerte"))
        foto("duele-4-recibido")
        p.tocar(etiqueta("duele-listo"))
        p.nodo(etiqueta("duele-avisada"))
        foto("duele-5-tarjeta", "duele-avisada")
    }

    @Test fun letraGrande() {
        tema = "grande"
        Telefono.shell("settings put system font_scale 1.5")
        enElEjercicio("vacio")
        foto("duele-0-ejercicio", "duele-abrir")
        p.tocar(etiqueta("duele-abrir"))
        completarYEnviar(capturas = true)
        foto("duele-4-recibido")
    }

    /** El menú tarda en irse: sin esperar, el toque siguiente cae en el menú de la fila anterior, que todavía se está cerrando. */
    private fun menuCerrado() = p.esperar("el menú se cerró") { ReglasSupleEstado.Estado.entries.none { p.existe(etiqueta("supl-estado-opcion-${it.clave}")) } }

    private fun marcar(n: Int, estado: String) {
        menuCerrado()
        p.tocar(etiqueta("supl-estado-$n"))
        p.tocar(etiqueta("supl-estado-opcion-$estado"))
        menuCerrado()
    }

    @Test fun marcarSuplementos() {
        val d = enSuplementacion("vacio")
        p.nodo(etiqueta("supl-estado"))
        p.nodo(texto("¿Ya lo tenés?"))
        assertEquals(listOf("0 de 4 marcados"), p.textosBajo(etiqueta("supl-estado-resumen")))
        assertEquals("Creatina monohidrato, Marcar", p.descripcion(etiqueta("supl-estado-0")))
        foto("suple-0-sin-marcar", "supl-estado")
        p.tocar(etiqueta("supl-estado-0"))
        p.nodo(etiqueta("supl-estado-opcion-comprado"))
        p.nodo(texto("Lo compré")); p.nodo(texto("Lo estoy tomando")); p.nodo(texto("No lo consigo")); p.nodo(texto("Lo dejé"))
        foto("suple-1-menu")
        p.tocar(etiqueta("supl-estado-opcion-comprado"))
        p.esperar("comprado") { p.descripcion(etiqueta("supl-estado-0")) == "Creatina monohidrato, Comprado" }
        p.esperar("1 de 4") { p.textosBajo(etiqueta("supl-estado-resumen")) == listOf("1 de 4 marcados") }
        marcar(0, "tomando")
        p.esperar("tomando") { p.descripcion(etiqueta("supl-estado-0")) == "Creatina monohidrato, Lo estás tomando" }
        marcar(1, "no_lo_consigo")
        p.nodo(etiqueta("supl-estado-no-consigo"))
        p.esperar("llegó al servidor") { d.marcas.toMap() == mapOf("creatina monohidrato" to "tomando", "omega 3" to "no_lo_consigo") }
        foto("suple-2-marcado", "supl-estado")
        // El protector de la muestra (un fármaco) y lo que sale no se marcan: 4 filas, no 6.
        assertFalse(p.existe(etiqueta("supl-estado-4")))
        assertTrue((0..3).none { "Telmis" in p.descripcion(etiqueta("supl-estado-$it")) || "Multivit" in p.descripcion(etiqueta("supl-estado-$it")) })
        // El protector sí está en «Tu día», como cualquier otro.
        p.nodo(etiqueta("suple-Telmisartán"))
    }

    @Test fun siFallaVuelveAtrasYAvisa() {
        val d = enSuplementacion("marcado")
        p.esperar("2 de 4") { p.textosBajo(etiqueta("supl-estado-resumen")) == listOf("2 de 4 marcados") }
        d.fallaMarcar = true
        marcar(1, "lo_deje")
        p.nodo(texto("No se pudo guardar. Probá de nuevo."))
        foto("suple-3-error")
        p.tocar(etiqueta("supl-estado-error-ok"))
        p.esperar("vuelve a como estaba") { p.descripcion(etiqueta("supl-estado-1")) == "Omega 3, Comprado" }
        assertEquals("comprado", d.marcas["omega 3"])
    }

    @Test fun suplementosYaMarcadosOscuroYSinPalanca() {
        tema = "oscuro"
        Telefono.modoNoche(true)
        enSuplementacion("marcado")
        p.esperar("2 de 4") { p.textosBajo(etiqueta("supl-estado-resumen")) == listOf("2 de 4 marcados") }
        aLaVista("supl-estado")
        p.tocar(etiqueta("supl-estado-3"))
        p.nodo(etiqueta("supl-estado-opcion-comprado"))
        foto("suple-1-menu")
        p.atras()
        foto("suple-2-marcado", "supl-estado")
    }

    @Test fun suplementosSinPalanca() {
        val d = enSuplementacion("apagado")
        p.nodo(texto("Tu día"))
        assertFalse("Con la palanca apagada no hay sección", p.existe(etiqueta("supl-estado")))
        assertTrue(d.llamadasFeedback.isEmpty())
    }
}
