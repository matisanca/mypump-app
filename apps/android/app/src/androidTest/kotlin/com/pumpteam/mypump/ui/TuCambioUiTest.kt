package com.pumpteam.mypump.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.diseno.ImagenesRemotas
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.TuCambio
import java.io.ByteArrayOutputStream
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Tu cambio» en Revisión (detrás de `check_guiado`) con el [ServidorDePrueba] (sin red) y fotos inventadas, dibujadas acá
 * (nunca fotos reales). Lo fino de la regla está en `TuCambioVectoresTest`; acá, lo que se ve. Capturas `tucambio-*`.
 */
@RunWith(AndroidJUnit4::class)
class TuCambioUiTest : PruebaUi() {
    private val lunes get() = FotosProgreso.lunes(FechaLocal.hoy())
    private fun haceSemanas(n: Int) = DiaCalendario.texto(DiaCalendario.numero(lunes)!! - 7L * n)

    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    /** [semanas]: hace cuántas semanas hay fotos de progreso (las tres poses). [inicio]: las de inicio, de hace 8 semanas. */
    private fun preparar(semanas: List<Int>, inicio: Boolean = false, palanca: Boolean = true) {
        servidor.respuestas["mypump_get_app_config"] = """{"check_guiado":$palanca,"fotos_inicio":$inicio}"""
        servidor.respuestas["mypump_check_guiado_get"] = """{"activo":true,"en_ciclo":false,"semana":"$lunes","catalogo":null,"senales":null}"""
        servidor.ponerFotos(semanas.associate { haceSemanas(it) to FotosProgreso.poses.map { p -> p.first } })
        // Un peso de hace 8 semanas y uno de la semana pasada, para el pie.
        servidor.respuestas["mypump_get_salud"] =
            """[{"fecha":"${haceSemanas(8)}","tipo":"peso_kg","valor":80.6,"fuente":"manual"},{"fecha":"${haceSemanas(1)}","tipo":"peso_kg","valor":78.2,"fuente":"manual"}]"""
        val tomada = DiaCalendario.texto(DiaCalendario.numero(haceSemanas(8))!! + 2) + "T15:00:00+00:00"
        servidor.respuestas["mypump_fotos_inicio_get"] = if (!inicio) """{"habilitado":false}""" else
            """{"habilitado":true,"completo":true,"nota":"","max_motivacion":4,"fotos":[""" +
                FotosProgreso.poses.joinToString(",") { """{"id":"ini-${it.first}","pose":"${it.first}","tomada_en":"$tomada","ancho":900,"alto":1200}""" } + "]}"
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if (pedido.ruta.endsWith("inicio/urls")) {
                Respuesta(200, ("""{"ok":true,"fotos":[""" + FotosProgreso.poses.joinToString(",") { """{"id":"ini-${it.first}","url":"https://fotos.prueba.invalid/inicio/${it.first}.jpg"}""" } + "]}").toByteArray())
            } else s.enviar(pedido)
        }
        ImagenesRemotas.bajar = { url -> imagen(url) }
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
    }

    /** Una imagen de prueba con un rótulo («inicio frente», «2026-11-02 perfil»), sin nada de una foto real. */
    private fun imagen(url: String): ByteArray {
        val partes = url.substringAfter(".invalid/").substringBefore(".jpg").split("/")
        val b = Bitmap.createBitmap(450, 600, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawColor(if (partes.firstOrNull() == "inicio") Color.rgb(70, 110, 80) else Color.rgb(110, 170, 120))
        val pintura = Paint().apply { color = Color.argb(90, 255, 255, 255) }
        c.drawOval(180f, 80f, 270f, 190f, pintura)
        c.drawRect(150f, 210f, 300f, 460f, pintura)
        val letra = Paint().apply { color = Color.WHITE; textSize = 40f; isAntiAlias = true; isFakeBoldText = true }
        partes.forEachIndexed { i, t -> c.drawText(t, 24f, 520f + i * 46f, letra) }
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }

    private fun mostrarTarjeta() {
        p.nodo(etiqueta("tucambio-tarjeta"))
        val delta = p.esperar("se ubica la tarjeta") {
            val visible = p.nodo(etiqueta("revision-lista"), ms = 0).boundsInRoot
            p.nodo(etiqueta("tucambio-tarjeta"), ms = 0).positionInRoot.y - visible.top - 24f
        }
        p.desplazar(etiqueta("revision-lista"), delta)
        p.quieto(800)
    }

    private fun y(tag: String) = p.nodo(etiqueta(tag)).positionInRoot.y

    @Test
    fun conLaPalancaApagadaEsLaRevisionDeSiempre() {
        preparar(listOf(8, 1), palanca = false)
        p.nodo(etiqueta("enviar-check"))
        assertFalse(p.existe(etiqueta("tucambio-tarjeta")))
        p.nodo(texto("El comparador antes/después se abre en 2 semanas más."))
    }

    @Test
    fun conUnaSemanaMuestraLaFotoYElTextoDeEspera() {
        preparar(listOf(1))
        p.nodo(etiqueta("tucambio-tarjeta"))
        assertTrue("va debajo del check", y("tucambio-tarjeta") > y("check-guiado-tarjeta"))
        assertEquals(listOf(TuCambio.TEXTO_ESPERA), p.textosBajo(etiqueta("tucambio-espera")))
        assertEquals("Foto de la semana 1", p.descripcion(etiqueta("tucambio-antes")))
        assertFalse(p.existe(etiqueta("tucambio-despues")))
        assertFalse("con una semana no hay nada que elegir", p.existe(etiqueta("tucambio-pose-frente")))
    }

    @Test
    fun conDosSemanasMuestraElParYAbreElComparador() {
        preparar(listOf(8, 1))
        p.nodo(etiqueta("tucambio-pie"))
        assertTrue("va debajo del check", y("tucambio-tarjeta") > y("check-guiado-tarjeta"))
        assertEquals("Foto de la semana 1", p.descripcion(etiqueta("tucambio-antes")))
        assertTrue(p.descripcion(etiqueta("tucambio-despues")).startsWith("Foto de la semana del "))
        assertEquals(listOf("7 semanas · -2,4 kg"), p.textosBajo(etiqueta("tucambio-pie")))
        assertTrue(p.seleccionado(etiqueta("tucambio-pose-frente")))
        p.tocar(etiqueta("tucambio-pose-perfil"))
        p.esperar("perfil elegido") { p.seleccionado(etiqueta("tucambio-pose-perfil")) && !p.seleccionado(etiqueta("tucambio-pose-frente")) }
        assertFalse(p.existe(texto("El comparador antes/después se abre en 2 semanas más.")))
        mostrarTarjeta()
        p.tocar(etiqueta("tucambio-ver"))
        p.nodo(etiqueta("tucambio-comparador"))
        assertTrue("abre en la pose elegida", p.seleccionado(etiqueta("tucambio-pose-perfil")))
        p.tocar(etiqueta("galeria-listo"))
        p.nodo(etiqueta("tucambio-tarjeta"))
    }

    @Test
    fun conFotosDeInicioLaSemanaUnoEsLaDeInicio() {
        // Sin las de inicio sería una sola semana: el par sale porque la semana 1 es la de inicio.
        preparar(listOf(1), inicio = true)
        p.nodo(etiqueta("tucambio-pie"), ms = 30_000)
        assertTrue(p.textosBajo(etiqueta("tucambio-pie")).single().startsWith("7 semanas"))
        assertFalse(p.existe(etiqueta("tucambio-espera")))
    }

    @Test
    fun conSoloFotosDeInicioEspera() {
        preparar(emptyList(), inicio = true)
        p.nodo(etiqueta("tucambio-espera"), ms = 30_000)
        p.esperar("la foto de inicio") { p.existe(etiqueta("tucambio-antes")) }
        assertEquals("Foto de la semana 1", p.descripcion(etiqueta("tucambio-antes")))
    }

    private fun enviarCheck() {
        p.tocar(etiqueta("check-guiado-abrir"))
        p.nodo(etiqueta("cg-paso-${CheckGuiado.Paso.PESO.clave}"))
        p.tocar(etiqueta("cg-omitir"))
        p.nodo(etiqueta("cg-paso-${CheckGuiado.Paso.ESCALAS.clave}"))
        for ((clave, n) in listOf("energia" to 4, "descanso" to 3, "hambre" to 2, "adherencia" to 5)) p.tocar(etiqueta("cg-escala-$clave-$n"))
        p.tocar(etiqueta("cg-seguir"))
        p.nodo(etiqueta("cg-paso-${CheckGuiado.Paso.FOTOS.clave}"))
        p.tocar(etiqueta("cg-omitir"))
        p.nodo(etiqueta("cg-paso-${CheckGuiado.Paso.SENALES.clave}"))
        p.tocar(etiqueta("cg-senal-ninguno"))
        p.tocar(etiqueta("cg-seguir"))
        p.nodo(etiqueta("cg-paso-${CheckGuiado.Paso.NOTA.clave}"))
        p.tocar(etiqueta("cg-seguir"))
        p.tocar(etiqueta("cg-enviar"))
        p.nodo(etiqueta("cg-listo"), ms = 30_000)
    }

    @Test
    fun listoMuestraElParDeFrente() {
        preparar(listOf(8, 1))
        enviarCheck()
        p.nodo(etiqueta("cg-listo-tucambio"))
        assertEquals("Foto de la semana 1", p.descripcion(etiqueta("tucambio-antes")))
        assertTrue(p.textosBajo(etiqueta("cg-listo-pie")).single().startsWith("7 semanas"))
        p.tocar(etiqueta("cg-cerrar-listo"))
        p.nodo(etiqueta("tucambio-tarjeta"))
    }

    @Test
    fun listoSinDosSemanasEsElDeSiempre() {
        preparar(listOf(1))
        enviarCheck()
        assertFalse(p.existe(etiqueta("cg-listo-tucambio")))
    }

    private fun capturas(tema: String) {
        preparar(listOf(8, 1))
        mostrarTarjeta(); Telefono.captura("tucambio-1-par-$tema")
        p.tocar(etiqueta("tucambio-ver")); p.nodo(etiqueta("tucambio-comparador")); p.quieto(800); Telefono.captura("tucambio-2-comparador-$tema")
        p.tocar(etiqueta("galeria-listo"))
        enviarCheck(); p.nodo(etiqueta("cg-listo-tucambio")); p.quieto(800); Telefono.captura("tucambio-5-listo-$tema")
    }

    @Test fun capturasClaro() = capturas("claro")

    @Test
    fun capturasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        capturas("oscuro")
    }

    @Test
    fun capturasLetraGrande() {
        Telefono.shell("settings put system font_scale 1.5")
        capturas("grande")
    }

    @Test
    fun capturasUnaSemanaYConInicio() {
        preparar(listOf(1), inicio = true)
        p.nodo(etiqueta("tucambio-pie"), ms = 30_000); mostrarTarjeta(); Telefono.captura("tucambio-4-con-inicio-claro")
    }
}
