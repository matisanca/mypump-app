package com.pumpteam.mypump.ui

import android.net.ConnectivityManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Lo que ve el cliente cuando falla la red, con el [ServidorDePrueba] fallando a pedido (paridad ACC-05, GEN-04 y OFF-06):
 * la pantalla «Sin conexión» con su única recarga sola al volver la red, el aviso de guardado con sus tiempos (los de
 * Pestanas.kt, como AvisoGuardado.swift de iOS) y el «Sin conexión, se reintenta solo» de la cola.
 *
 * La red de ACC-05 es la de verdad (el modo avión del emulador): la app escucha al sistema para saber que volvió, no al
 * servidor de prueba. Al terminar, el modo avión queda apagado.
 */
@RunWith(AndroidJUnit4::class)
class RedYGuardadoUiTest : PruebaUi() {
    private var avionPrendido = false

    @After
    fun devolverLaRed() {
        if (avionPrendido) modoAvion(false)
    }

    /** El modo avión de verdad, esperando a que el sistema lo vea (la red vuelve en unos segundos). */
    private fun modoAvion(prendido: Boolean) {
        Telefono.shell("cmd connectivity airplane-mode ${if (prendido) "enable" else "disable"}")
        avionPrendido = prendido
        val cm = app.getSystemService(ConnectivityManager::class.java)
        p.esperar(if (prendido) "el teléfono sin red" else "el teléfono con red", ms = 60_000, enElPrincipal = false) {
            (cm.activeNetwork == null) == prendido
        }
    }

    private fun cargas() = servidor.a("mypump_get_cliente_info").size

    /** Los pesos que intentaron salir (el peso va por `ingest_salud`, con el tipo `peso_kg`). */
    private fun pesos() = servidor.a("mypump_ingest_salud").count { "peso_kg" in it }

    /** Revisión, en Peso corporal: el peso de hoy sale por la cola (con la misma clave en el día: el último gana). */
    private fun irAlPeso() {
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("guardar-peso"))
    }

    private fun guardarPeso(kilos: String) {
        p.escribir(etiqueta("peso-hoy"), kilos)
        p.tocar(etiqueta("guardar-peso"))
    }

    private fun aviso(t: String): Boolean = p.existe(texto(t))

    /**
     * ACC-05: sin red y sin copia guardada, «Sin conexión» con Reintentar. Al volver la red recarga sola UNA vez: si la señal
     * va y viene no vuelve a recargar sola (no es un bucle contra un servicio que no contesta), y Reintentar sigue andando.
     */
    @Test
    fun sinRedNiCopiaAlVolverLaRedRecargaUnaSolaVez() {
        modoAvion(true)
        servidor.sinRed = true
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("sin-conexion"))
        p.nodo(texto("Sin conexión"))
        p.nodo(texto("No pudimos traer tu plan. Cuando vuelva la señal lo intentamos solos."))
        p.nodo(etiqueta("reintentar"))
        p.quieto(1_000)
        val antes = cargas()
        // Vuelve la señal (el servicio todavía no contesta): recarga sola, una vez.
        modoAvion(false)
        p.esperar("la recarga sola al volver la red", ms = 30_000, enElPrincipal = false) { cargas() > antes }
        p.quieto(3_000)
        assertEquals("al volver la red tiene que recargar una sola vez", antes + 1, cargas())
        p.nodo(etiqueta("sin-conexion"))
        // La señal se va y vuelve otra vez: no recarga sola de nuevo.
        modoAvion(true)
        modoAvion(false)
        p.quieto(5_000)
        assertEquals("con la señal yendo y viniendo no puede recargar en bucle", antes + 1, cargas())
        // Reintentar a mano, con el servicio de vuelta, entra.
        servidor.sinRed = false
        p.tocar(etiqueta("reintentar"))
        p.nodo(etiqueta("pestana-entreno"))
    }

    /**
     * GEN-04: el aviso de guardado. Un guardado rápido no dice nada; uno que tarda más de 900 ms dice «Guardando…», nunca
     * antes, y se va al terminar sin decir «Guardado» (eso es solo después de un problema); después de un problema, cuando
     * por fin sale, «Guardado» un momento.
     */
    @Test
    fun elAvisoDeGuardadoSaleSoloSiTardaYGuardadoDespuesDeUnProblema() {
        guardarCuenta()
        abrir()
        irAlPeso()
        // Rápido: sale sin aviso.
        val n0 = pesos()
        guardarPeso("80")
        p.esperar("salió por la cola") { pesos() > n0 }
        p.quieto(1_500)
        assertFalse("un guardado rápido no avisa nada: ${p.resumen()}", p.existe(etiqueta("aviso-guardado")))
        // Lento (2,5 s): «Guardando…» pasados los 900 ms, mientras manda, y se va al terminar.
        servidor.demoraMs = 2_500
        guardarPeso("80,5")
        Thread.sleep(400)
        assertFalse("«Guardando…» antes de los 900 ms", aviso("Guardando…"))
        p.esperar("«Guardando…» mientras tarda", ms = 2_000) { aviso("Guardando…") }
        p.esperar("el aviso se va al terminar", ms = 8_000) { !p.existe(etiqueta("aviso-guardado")) }
        assertFalse("«Guardado» es solo después de un problema", aviso("Guardado"))
        servidor.demoraMs = 0
        // Con un problema (sin red) y después sale: «Guardado».
        servidor.sinRed = true
        guardarPeso("81")
        p.esperar("el problema") { aviso("Sin conexión, se reintenta solo") }
        servidor.sinRed = false
        p.esperar("«Guardado» cuando por fin sale", ms = 20_000) { aviso("Guardado") }
        p.esperar("y se va solo", ms = 6_000) { !p.existe(etiqueta("aviso-guardado")) }
    }

    /**
     * OFF-06: si la cola no puede mandar, «Sin conexión, se reintenta solo». El aviso se va solo (no tapa la pantalla), la
     * cola lo sigue intentando sin que el cliente toque nada y, cuando vuelve el servicio, sale.
     */
    @Test
    fun siLaColaNoPuedeMandarAvisaQueSeReintentaSolo() {
        guardarCuenta()
        abrir()
        irAlPeso()
        servidor.sinRed = true
        val n0 = pesos()
        guardarPeso("80")
        p.esperar("«Sin conexión, se reintenta solo»") { aviso("Sin conexión, se reintenta solo") }
        assertTrue("el peso no intentó salir", pesos() > n0)
        p.esperar("el aviso se va solo", ms = 8_000) { !p.existe(etiqueta("aviso-guardado")) }
        // Sin tocar nada, la cola lo vuelve a intentar.
        val intentos = pesos()
        p.esperar("la cola reintenta sola", ms = 20_000, enElPrincipal = false) { pesos() > intentos }
        // Vuelve el servicio: sale solo.
        servidor.sinRed = false
        val alVolver = pesos()
        p.esperar("salió al volver el servicio", ms = 40_000, enElPrincipal = false) { pesos() > alVolver }
        p.esperar("«Guardado»", ms = 10_000) { aviso("Guardado") }
    }
}
