package com.pumpteam.mypump.ui

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * GEN-08, «Quitar animaciones» de Accesibilidad (el Reducir movimiento de iOS): con la escala de animaciones en 0 se
 * apagan las animaciones continuas, que leen `reducirMovimiento()`:
 * - las fotos de Inicio y Pico que se alternan solas (`ImagenesMovimiento`);
 * - el pulso de «En curso» (`CronometroSesion`);
 * - el brillo del esqueleto de carga (`Modifier.esqueleto`).
 *
 * La alternancia es la que muerde: corre con una espera y no con el reloj de animaciones, así que solo la frena la app. El
 * pulso y el brillo los congela además el propio Compose con la escala en 0: se mira que no se dibujen.
 *
 * El ajuste es del teléfono (`settings put global animator_duration_scale`): al terminar queda como estaba.
 */
@RunWith(AndroidJUnit4::class)
class MovimientoReducidoUiTest : PruebaUi() {
    private var escalaAntes: String? = null

    @Before
    fun anotarLaEscala() {
        escalaAntes = Telefono.shell("settings get global animator_duration_scale").trim()
    }

    @After
    fun devolverLaEscala() {
        val antes = escalaAntes ?: return
        if (antes.isEmpty() || antes == "null") {
            Telefono.shell("settings delete global animator_duration_scale")
        } else {
            Telefono.shell("settings put global animator_duration_scale $antes")
        }
    }

    private fun escala(valor: String) {
        Telefono.shell("settings put global animator_duration_scale $valor")
    }

    /** La cuenta con un ejercicio que trae las dos fotos (inicio y pico), sin sesión ni historial. */
    private fun abrirConFotos() {
        val progresion = (1..4).joinToString(",") { """{"semana":$it,"series":2,"reps":"8","rir":"1"}""" }
        servidor.respuestas["mypump_get_rutina_activa"] =
            """[{"id":"r-fotos","version":1,"semana_actual":1,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — PECHO","ejercicios":[
              {"id":"press-d1-0","nombre":"Press banca plano con barra (pectoral)","tipo":"compuesto","descanso_segundos":120,
               "images":{"eccentric":"https://fotos.prueba.invalid/press/0.jpg","concentric":"https://fotos.prueba.invalid/press/1.jpg"},
               "progresion":[$progresion]}]}]}]}}]"""
        servidor.respuestas["mypump_get_historico_por_clave"] = "[]"
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
    }

    private fun abrirElEjercicio() {
        p.tocar(etiqueta("ejercicio-press-d1-0"))
        p.nodo(etiqueta("como-se-hace"))
        p.nodo(etiqueta("foto-Pico"))
    }

    /** Qué foto se vio elegida durante [ms] (la alternancia pasa de una a otra cada 1,6 s). */
    private fun elegidasDurante(ms: Long): Set<String> {
        val vistas = HashSet<String>()
        val fin = SystemClock.uptimeMillis() + ms
        while (SystemClock.uptimeMillis() < fin) {
            for (f in listOf("Inicio", "Pico")) if (p.seleccionado(etiqueta("foto-$f"))) vistas += f
            Thread.sleep(80)
        }
        return vistas
    }

    @Test
    fun sinAnimacionesNadaSeMueveSolo() {
        escala("0")
        abrirConFotos()
        // El pulso de «En curso»: con la sesión corriendo solo se redibuja el tiempo, una vez por segundo.
        p.tocar(etiqueta("empezar-entrenamiento"))
        p.nodo(etiqueta("cronometro"))
        p.quieto(500)
        val cuadros = p.dibujosEn(2_000)
        assertTrue("el pulso de «En curso» se sigue dibujando: $cuadros cuadros en 2 s", cuadros <= 6)
        // Las fotos del movimiento quedan en Inicio: no se alternan solas.
        abrirElEjercicio()
        assertEquals(setOf("Inicio"), elegidasDurante(4_000))
        // Elegir una a mano sigue andando.
        p.tocar(etiqueta("foto-Pico"))
        p.esperar("Pico elegida") { p.seleccionado(etiqueta("foto-Pico")) }
        // El esqueleto de Progreso, mientras carga, queda quieto (sin el brillo que lo cruza).
        p.tocar(etiqueta("volver"))
        p.nodo(etiqueta("cronometro"))
        servidor.demoraMs = 10_000
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-cargando"), ms = 20_000)
        p.esperar("el esqueleto quieto", ms = 8_000, enElPrincipal = false) { Telefono.quietoConTope(2_000) && p.dibujosEn(600) == 0 }
        assertTrue("el esqueleto se fue antes de mirarlo", p.existe(etiqueta("progreso-cargando")))
        servidor.demoraMs = 0
    }

    /**
     * Con animaciones las fotos se alternan; si el cliente las quita con la app abierta, se frenan en ese momento (antes se
     * leía el ajuste una vez y la pantalla abierta seguía igual), y si las vuelve a poner, siguen.
     */
    @Test
    fun alQuitarlasConLaAppAbiertaSeFrenanEnElMomento() {
        escala("1")
        abrirConFotos()
        abrirElEjercicio()
        assertEquals("con animaciones se alternan", setOf("Inicio", "Pico"), elegidasDurante(4_000))
        escala("0")
        Thread.sleep(600)
        val quietas = elegidasDurante(4_000)
        assertEquals("con la escala en 0 se tienen que frenar: $quietas", 1, quietas.size)
        escala("1")
        Thread.sleep(600)
        assertEquals("con animaciones otra vez, siguen", setOf("Inicio", "Pico"), elegidasDurante(4_000))
    }
}
