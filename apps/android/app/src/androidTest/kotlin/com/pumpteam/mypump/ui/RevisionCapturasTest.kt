package com.pumpteam.mypump.ui

import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.ImagenesRemotas
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.salud.EstadoHealthConnect
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia de Revisión, en claro y en oscuro (como `CapturasUiTest`): las fotos, el check, la galería
 * con el comparador (6 semanas de fotos, que en iOS no se pudieron sembrar por la ventana del servidor) y la demo. Desde
 * la 2.1 el peso, Mi reloj y la recuperación tienen sus capturas en `SaludCapturasTest`. Las miniaturas son siluetas lisas armadas acá: las URLs firmadas de
 * prueba no van a la red. Quedan en [Telefono.CARPETA_CAPTURAS] y las baja `scripts/nativa/emu-ui.sh`.
 */
@RunWith(AndroidJUnit4::class)
class RevisionCapturasTest : PruebaUi() {
    @After
    fun sacarSalud() {
        ModeloSalud.fuenteDelSistema = null
        EstadoHealthConnect.forzado = null
    }

    @Test
    fun enClaro() = recorrer(oscuro = false)

    @Test
    fun enOscuro() = recorrer(oscuro = true)

    /** Lleva la sección arriba de todo con el desplazamiento de la lista (la acción de accesibilidad). */
    private fun llevarArriba(etiquetaDe: String) {
        val delta = p.esperar("se ubica $etiquetaDe") {
            val visible = p.nodo(etiqueta("revision-lista"), ms = 0).boundsInRoot
            p.nodo(etiqueta(etiquetaDe), ms = 0).positionInRoot.y - visible.top - 24f
        }
        p.desplazar(etiqueta("revision-lista"), delta)
        p.quieto(400)
    }

    private fun sembrar() {
        val hoy = DiaCalendario.numero(FechaLocal.hoy())!!
        val lunes = DiaCalendario.numero(FotosProgreso.lunes(FechaLocal.hoy()))!!
        // Seis semanas completas hasta la pasada y, esta, frente y perfil.
        val semanas = (1..6).map { DiaCalendario.texto(lunes - 7L * it) }
        servidor.ponerFotos(semanas.associateWith { listOf("frente", "perfil", "espalda") } + (DiaCalendario.texto(lunes) to listOf("frente", "perfil")))
        val tonos = mapOf("frente" to Color.rgb(92, 124, 153), "perfil" to Color.rgb(120, 104, 150), "espalda" to Color.rgb(96, 140, 110))
        ImagenesRemotas.bajar = { url -> tonos.entries.firstOrNull { "/${it.key}.jpg" in url }?.let { FotoDePrueba.miniatura(it.value) } }
        // Oura para conectar y WHOOP conectado.
        servidor.relojes = listOf("oura", "whoop")
        servidor.respuestas["mypump_get_conexiones"] = """[{"proveedor":"whoop","estado":"conectada","ultimo_pull_en":"2026-10-14T07:10:00Z"}]"""
        // Recuperación y Salud con los datos de reloj de la cuenta de iOS.
        ModeloSalud.fuenteDelSistema = FuenteDeMentira()
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
        for (f in listOf("get_salud", "get_recuperacion", "get_mostrar_recuperacion")) {
            servidor.respuestas["mypump_$f"] = instr.context.assets.open("test-nativa-ios/$f.json").use { it.readBytes().toString(Charsets.UTF_8) }
        }
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
    }

    private fun recorrer(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        sembrar()
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("seccion-check"))
            p.esperar("las miniaturas") { servidor.a("urls").firstOrNull() }
            p.quieto(800)
            foto("revision-01-fotos")
            llevarArriba("seccion-check")
            for (t in listOf("Energía: 4 de 5", "Descanso: 3 de 5", "Hambre: 2 de 5")) p.tocar(texto(t))
            p.escribir(etiqueta("peso-check"), "80,4")
            p.nodo(texto("Faltan: Adherencia"))
            foto("revision-02-check")
            // Desde la 2.1 Revisión termina en el check: el peso, Mi reloj, la recuperación y la salud están en Salud
            // (las capturas de SaludCapturasTest).
            assertFalse(p.existe(etiqueta("seccion-peso")) || p.existe(etiqueta("card-recuperacion")) || p.existe(etiqueta("card-reloj")))
            llevarArriba("seccion-fotos")
            p.tocar(etiqueta("ver-mis-fotos"))
            p.nodo(etiqueta("comparador"))
            p.quieto(800)
            foto("revision-08-galeria-comparador")
            p.tocar(etiqueta("galeria-listo"))
            p.esperarQueNoEste(etiqueta("galeria-fotos"))
        }.close()

        // La demo: sin fotos.
        reiniciarEstado()
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("seccion-check"))
            p.tocar(etiqueta("foto-frente"))
            p.nodo(texto("En la demo las fotos no se guardan."))
            foto("revision-09-demo")
        }.close()
    }
}
