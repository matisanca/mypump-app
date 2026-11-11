package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import org.junit.After
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

/**
 * La galería del diseño de la carga (gemelo de `testGaleriaDeDiseno` de iOS): cada estado del panel y de la tarjeta, en claro,
 * en oscuro y con letra grande. Solo saca capturas; lo que se comprueba está en [CargaSimpleUiTest]. Corre solo con
 * `-e galeria 1`.
 */
@RunWith(AndroidJUnit4::class)
class CargaDisenoGaleriaTest : PruebaUi() {
    private val lugar = "jalon-al-pecho-prono-dorsal-ancho-d1-0"

    private fun soloConGaleria() =
        assumeTrue("solo con -e galeria 1", InstrumentationRegistry.getArguments().getString("galeria") == "1")

    @After
    fun letraNormal() {
        Telefono.shell("settings put system font_scale 1.0")
    }

    @Test fun galeriaClaro() = galeria("claro")
    @Test fun galeriaOscuro() = galeria("oscuro")
    @Test fun galeriaLetraGrande() = galeria("grande")

    /**
     * La semana 2 baja de 12 a 10 reps con las mismas series: la app sugiere subir. Con el curl con barra Z (17,5 kg → 20): el
     * jalón está en 58 kg en máquina, y de a 5 kg el próximo pasa la subida máxima, así que ahí no corresponde.
     */
    @Test fun aumentoClaro() = aumento("claro")
    @Test fun aumentoOscuro() = aumento("oscuro")

    private fun lanzar(modo: String, semana: Int? = null, ejercicio: String = lugar) {
        soloConGaleria()
        Telefono.modoNoche(modo == "oscuro")
        if (modo == "grande") Telefono.shell("settings put system font_scale 1.3")
        if (semana != null) {
            val rutina = InstrumentationRegistry.getInstrumentation().context.assets.open("test-nativa-real/get_rutina_activa.json")
                .use { it.readBytes().toString(Charsets.UTF_8) }
            val l = JSONArray(rutina)
            l.getJSONObject(0).put("semana_actual", semana)
            servidor.respuestas["mypump_get_rutina_activa"] = l.toString()
        }
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
        // En la lista: ahí se ven juntos la tarjeta (la carga y las series) y el panel.
        abrirEnLaLista(ejercicio)
        p.nodo(etiqueta("fila-serie-1"))
        p.esperar("la carga de la vez pasada") { p.textoDe(etiqueta("carga-valor")).takeIf { it.isNotEmpty() } }
        mostrar(etiqueta("carga-valor"))
    }

    /** Desplaza la lista hasta que [s] quede a [arriba] px del borde de arriba (como en GuiaUiTest). */
    private fun mostrar(s: Selector, arriba: Float = 330f) {
        repeat(20) {
            val n = p.nodo(s)
            val listo = p.enPrincipal<Boolean> {
                val b = n.boundsInRoot
                var q = n.parent
                while (q != null && q.config.getOrNull(SemanticsActions.ScrollBy) == null) q = q.parent
                val scroll = q?.config?.getOrNull(SemanticsActions.ScrollBy)?.action ?: return@enPrincipal true
                val dy = if (b.height <= 0f) 400f else b.top - arriba
                if (abs(dy) < 40f) return@enPrincipal true
                scroll.invoke(0f, dy.coerceIn(-600f, 600f))
                false
            }
            p.quieto(300)
            if (listo) return
        }
    }

    private fun galeria(modo: String) {
        lanzar(modo)
        fun foto(n: String) = Telefono.captura("carga-diseno-$n-$modo")
        foto("01-inicio")
        p.tocar(etiqueta("reps-mas"))
        p.quieto(500)
        foto("02-reps-de-mas")
        p.tocar(etiqueta("reps-menos"))
        darOK()
        esperarHecha(1)
        p.nodo(etiqueta("deshacer-ok"))
        foto("03-hecha-y-deshacer")
        // La guardia: otro OK al instante pide un segundo toque.
        p.quieto(700)
        p.tocar(etiqueta("ok-serie"))
        p.esperar("la guardia") { p.descripcion(etiqueta("ok-serie")).startsWith("¿Ya hiciste").takeIf { it } }
        foto("04-guardia")
        darOK()   // el segundo toque (y otro si el emulador llegó tarde a la ventana)
        esperarHecha(2)
        p.esperarQueNoEste(etiqueta("deshacer-ok"), ms = 12_000)
        foto("05-dos-hechas")
        mostrar(etiqueta("fila-serie-1"), arriba = 260f)
        p.tocar(etiqueta("fila-serie-1"))
        p.nodo(etiqueta("correccion-guardar"))
        foto("06-correccion")
        p.tocar(etiqueta("correccion-guardar"))
        p.esperarQueNoEste(etiqueta("correccion-guardar"))
        p.tocar(etiqueta("toggle-mismo-peso"))
        p.nodo(etiqueta("kg-serie-3"))
        mostrar(etiqueta("fila-serie-1"), arriba = 260f)
        foto("07-peso-por-serie")
    }

    private fun aumento(modo: String) {
        lanzar(modo, semana = 2, ejercicio = "curl-con-barra-z-biceps-d1-2")
        fun foto(n: String) = Telefono.captura("carga-diseno-$n-$modo")
        p.nodo(etiqueta("aumento-subir"))
        foto("08-aumento")
        p.tocar(etiqueta("aumento-subir"))
        p.nodo(etiqueta("aumento-volver"))
        p.quieto(300)
        foto("09-aumento-aceptado")
    }
}
