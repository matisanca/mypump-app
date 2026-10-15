package com.pumpteam.mypump.diseno

import androidx.compose.runtime.AbstractApplier
import androidx.compose.runtime.BroadcastFrameClock
import androidx.compose.runtime.Composition
import androidx.compose.runtime.Recomposer
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

private class ApplierNulo : AbstractApplier<Unit>(Unit) {
    override fun insertTopDown(index: Int, instance: Unit) {}
    override fun insertBottomUp(index: Int, instance: Unit) {}
    override fun remove(index: Int, count: Int) {}
    override fun move(from: Int, to: Int, count: Int) {}
    override fun onClear() {}
}

/**
 * [estadoImagenRemota] con el runtime de Compose de la app y una carga falsa (revisión adversarial del 15-oct): al cambiar la
 * URL (reemplazar la foto de una pose, cambiar de día en Entreno, sustituir un ejercicio) se seguía viendo la foto vieja.
 */
class EstadoImagenRemotaTest {
    @Test
    fun alCambiarLaUrlSeVeLaFotoNueva() = runBlocking {
        val reloj = BroadcastFrameClock()
        val recomposer = Recomposer(coroutineContext + reloj)
        val corre = launch(reloj) { recomposer.runRecomposeAndApplyChanges() }
        val composicion = Composition(ApplierNulo(), recomposer)
        val url = mutableStateOf<String?>("https://fotos/2026-10-12/frente.jpg?firma=1")
        val memoria = HashMap<String, String>()
        val pedidas = ArrayList<String>()
        var vista: String? = null
        var termino = false
        composicion.setContent {
            val (imagen, listo) = estadoImagenRemota(
                url.value, 200,
                enMemoria = { u, _ -> memoria[u] },
                cargar = { u, _ ->
                    pedidas += u
                    delay(5)
                    "bitmap de $u".also { memoria[u] = it }
                },
            )
            vista = imagen
            termino = listo
        }
        suspend fun asentar() = repeat(40) {
            Snapshot.sendApplyNotifications()
            reloj.sendFrame(System.nanoTime())
            delay(5)
        }
        asentar()
        assertEquals("bitmap de https://fotos/2026-10-12/frente.jpg?firma=1", vista)
        // Se reemplazó la foto de frente: `firmar()` trae otra URL para la misma pose.
        url.value = "https://fotos/2026-10-12/frente.jpg?firma=2"
        asentar()
        composicion.dispose()
        // El recomposer es hijo de runBlocking: sin cancelarlo, la prueba no termina nunca (con la aserción en verde).
        recomposer.cancel()
        corre.cancel()
        assertEquals("bitmap de https://fotos/2026-10-12/frente.jpg?firma=2", vista, "sigue la foto de la URL vieja; pedidas=$pedidas")
        assertEquals(true, termino)
        assertEquals(2, pedidas.size)
    }
}
