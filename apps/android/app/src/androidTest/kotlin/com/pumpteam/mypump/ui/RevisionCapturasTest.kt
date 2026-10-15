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
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia de Revisión, en claro y en oscuro (como `CapturasUiTest`): cada sección arriba de todo, Mi
 * Día con la recuperación, los 30 días, la galería con el comparador (6 semanas de fotos, que en iOS no se pudieron
 * sembrar por la ventana del servidor) y la demo. Las miniaturas son siluetas lisas armadas acá: las URLs firmadas de
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
        // Mi Día con historia: 9 días seguidos, hoy entrené y comí según el plan, 5 vasos (los bocetos llenos de iOS).
        servidor.respuestas["mypump_get_streak"] = """[{"streak":9,"ultimo_dia_valido":"${DiaCalendario.texto(hoy - 1)}"}]"""
        servidor.respuestas["mypump_get_habitos_dia"] =
            """[{"fecha":"${FechaLocal.hoy()}","entrenamiento":"entrene","comio_segun_plan":true,"durmio_bien":false,"cardio":null,"vasos_agua":5}]"""
        val patron = listOf(
            false, true, true, true, true, true, true, true, true, true, false, true, true, false, true,
            true, true, false, false, true, true, true, true, false, true, true, true, true, false, false,
        )
        servidor.respuestas["mypump_get_adherencia_30d"] = patron.mapIndexed { i, valido ->
            val parcial = !valido && i % 3 == 0
            val entreno = if (valido) (if (i % 2 == 0) "\"entrene\"" else "\"descanso\"") else if (parcial) "\"entrene\"" else "null"
            """{"fecha":"${DiaCalendario.texto(hoy - i)}","entrenamiento":$entreno,"comio_segun_plan":${if (valido || parcial) "true" else "null"},"durmio_bien":${if (valido) "true" else "null"},"vasos_agua":${if (valido) 8 else 2},"es_valido":$valido}"""
        }.joinToString(",", "[", "]")
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
            p.nodo(etiqueta("seccion-midia"))
            p.esperar("las miniaturas") { servidor.a("urls").firstOrNull() }
            p.quieto(800)
            foto("revision-01-fotos")
            llevarArriba("seccion-check")
            for (t in listOf("Energía: 4 de 5", "Descanso: 3 de 5", "Hambre: 2 de 5")) p.tocar(texto(t))
            p.nodo(texto("Faltan: Adherencia"))
            foto("revision-02-check")
            llevarArriba("seccion-peso")
            foto("revision-03-peso")
            llevarArriba("seccion-reloj")
            foto("revision-04-mi-reloj")
            llevarArriba("seccion-midia")
            foto("revision-05-mi-dia")
            llevarArriba("card-recuperacion")
            foto("revision-06-recuperacion-y-salud")
            p.tocar(etiqueta("ultimos-30"))
            p.nodo(etiqueta("grilla-30"))
            llevarArriba("ultimos-30")
            foto("revision-07-ultimos-30-dias")
            llevarArriba("seccion-fotos")
            p.tocar(etiqueta("ver-mis-fotos"))
            p.nodo(etiqueta("comparador"))
            p.quieto(800)
            foto("revision-08-galeria-comparador")
            p.tocar(etiqueta("galeria-listo"))
            p.esperarQueNoEste(etiqueta("galeria-fotos"))
        }.close()

        // La demo: Mi Día sembrado, sin fotos, reloj ni salud.
        reiniciarEstado()
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("seccion-midia"))
            p.tocar(etiqueta("foto-frente"))
            p.nodo(texto("En la demo las fotos no se guardan."))
            foto("revision-09-demo")
            llevarArriba("seccion-midia")
            foto("revision-10-demo-mi-dia")
        }.close()
    }
}
