package com.pumpteam.mypump.ui

import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleGimnasio
import com.pumpteam.mypump.datos.DobleTecnica
import com.pumpteam.mypump.datos.ModeloNovedades
import com.pumpteam.mypump.datos.NovedadPlan
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La simplificación de la 2.3.0 (OK de Mati del 11/11), de punta a punta y con capturas `simplificar-*` en claro, oscuro y
 * letra grande: «Tu inicio con Mati», el botón «Mis datos» con texto, Mis datos en tres grupos, «Mi progreso» en una columna
 * y las novedades del plan en Revisión (con la demo, sin red), y «Mi gimnasio y mi técnica» contra los dobles de gimnasio y
 * técnica (datos inventados). La tarjeta «Mi salud» de Entreno se captura en MiSaludUiTest.
 */
@RunWith(AndroidJUnit4::class)
class SimplificarUiTest : PruebaUi() {
    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    private fun tema(t: String) {
        if (t == "oscuro") {
            Telefono.modoNoche(true)
            guardarTemaOscuro()
        }
        if (t == "grande") Telefono.shell("settings put system font_scale 2.0")
    }

    private fun conLaDemo(t: String) {
        tema(t)
        val escena = abrir()
        p.tocar(etiqueta("ver-demo"))
        // La demo con una novedad de muestra, ya vista (la hoja que sale sola no tapa las capturas). Datos inventados.
        p.nodo(etiqueta("salir-demo"))
        val muestra = NovedadPlan(
            "simplificar-1", System.currentTimeMillis().toDouble(), "Cambió tu dieta",
            "Sumamos una colación a la tarde y bajamos un poco el arroz de la cena.", emptyList(), vista = true,
        )
        escena.onActivity { ViewModelProvider(it)[ModeloAppViewModel::class.java].modelo.value?.usarNovedadesDeMuestra(ModeloNovedades(listOf(muestra))) }
        // Tu guía, la videollamada y la lista previa: una sola tarjeta, con su título.
        p.nodo(etiqueta("inicio-con-mati"), 30_000)
        p.nodo(texto("Tu inicio con Mati"))
        assertTrue(p.encabezado(etiqueta("inicio-con-mati-titulo")))
        p.quieto(800)
        Telefono.captura("simplificar-2-inicio-con-mati-$t")

        // Revisión: el botón «Mis datos» con su texto y, más abajo, lo último que cambió en el plan.
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("mis-datos"))
        assertTrue(p.textosBajo(etiqueta("mis-datos")).contains("Mis datos"))
        p.quieto(800)
        Telefono.captura("simplificar-3-revision-$t")
        p.nodo(etiqueta("revision-novedades"), 30_000)
        p.nodo(texto("Lo último que cambió en tu plan"))
        // Hasta el bloque, para la captura (debajo de la devolución).
        // (El título de arriba se pliega con el primer desplazamiento y se come una parte: se insiste.)
        val y = { tag: String -> p.nodo(etiqueta(tag)).let { n -> p.enPrincipal { n.positionInRoot.y } } }
        repeat(6) {
            val falta = y("revision-novedades") - y("revision-lista") - 200f
            if (kotlin.math.abs(falta) < 60f) return@repeat
            p.desplazar(etiqueta("revision-lista"), falta)
            p.quieto(700)
        }
        p.quieto(500)
        Telefono.captura("simplificar-6-revision-novedades-$t")

        // Mis datos en tres grupos, sin las filas que se fueron a otro lado.
        p.tocar(etiqueta("mis-datos"))
        p.nodo(texto("Mi plan"))
        for (fuera in listOf("Mi gimnasio", "Mi técnica", "Novedades del plan")) assertFalse(fuera, p.existe(texto(fuera)))
        p.quieto(500)
        Telefono.captura("simplificar-4-mis-datos-$t")
        p.nodo(texto("Privacidad"))
        p.atras()
        p.nodo(etiqueta("mis-datos"))

        // «Mi progreso»: una columna con Recuperación (no se fue), Fuerza y Cuerpo.
        p.abrirSalud()
        p.nodo(texto("Mi progreso"))
        p.nodo(etiqueta("mi-progreso-recuperacion"))
        p.quieto(800)
        Telefono.captura("simplificar-5-mi-progreso-$t")
        p.verSeccion("fuerza")
        Telefono.captura("simplificar-5-mi-progreso-fuerza-$t")
    }

    @Test fun conLaDemoEnClaro() = conLaDemo("claro")

    @Test fun conLaDemoEnOscuro() = conLaDemo("oscuro")

    @Test fun conLaDemoConLetraGrande() = conLaDemo("grande")

    /** El gimnasio cargado (con «Entreno en casa») y una técnica con la respuesta de Mati de estos días. */
    private fun dondeEntreno(t: String) {
        tema(t)
        val g = DobleGimnasio.escenario("casaConGimnasioVigente")
        val tec = DobleTecnica.escenario("publicado")
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            val r = pedido.ruta
            when {
                r.endsWith("mypump_get_app_config") -> {
                    val junto = JSONObject(String(g.enviar(pedido).cuerpo))
                    val deTecnica = JSONObject(String(tec.enviar(pedido).cuerpo))
                    deTecnica.keys().forEach { junto.put(it, deTecnica.get(it)) }
                    Respuesta(200, junto.toString().toByteArray())
                }
                "tecnica" in r -> tec.enviar(pedido)
                "gimnasio" in r || "mypump_casa_" in r -> g.enviar(pedido)
                else -> s.enviar(pedido)
            }
        }
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-entreno"))
        // Al final de Entreno, un renglón grande y, con la respuesta reciente, el botón que la abre directo.
        p.nodo(etiqueta("donde-entreno-respuesta"), 30_000)
        p.nodo(texto("Mi gimnasio y mi técnica"))
        // Hasta el renglón (al final de la lista), para la captura.
        val tope = { tag: String -> p.nodo(etiqueta(tag)).let { n -> p.enPrincipal { n.positionInRoot.y } } }
        p.desplazar(etiqueta("entreno-lista"), tope("donde-entreno-entrada") - tope("entreno-lista") - 300f)
        p.quieto(800)
        Telefono.captura("simplificar-7-entrada-donde-entreno-$t")
        p.tocar(etiqueta("donde-entreno-entrada"))
        p.nodo(etiqueta("donde-entreno"))
        p.nodo(etiqueta("donde-entreno-bloque-gimnasio"))
        p.nodo(etiqueta("casa-interruptor"))
        p.nodo(etiqueta("donde-entreno-bloque-tecnica"))
        p.quieto(800)
        Telefono.captura("simplificar-8-mi-gimnasio-y-mi-tecnica-$t")
        // Atrás vuelve a Entreno; la respuesta está a un toque.
        p.atras()
        p.tocar(etiqueta("donde-entreno-respuesta"))
        p.nodo(etiqueta("tecnica-credito"))
        p.quieto(500)
        Telefono.captura("simplificar-9-respuesta-tecnica-$t")
    }

    @Test fun dondeEntrenoEnClaro() = dondeEntreno("claro")

    @Test fun dondeEntrenoEnOscuro() = dondeEntreno("oscuro")

    @Test fun dondeEntrenoConLetraGrande() = dondeEntreno("grande")
}
