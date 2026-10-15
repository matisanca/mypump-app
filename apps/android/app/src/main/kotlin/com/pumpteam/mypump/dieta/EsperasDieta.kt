package com.pumpteam.mypump.dieta

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Resultado
import com.pumpteam.mypump.modelos.ValorJson
import java.util.WeakHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Lo de Dieta que espera a la IA (la foto del plato y la de la etiqueta: ~30 s, hasta 150, y gastan cupo) vive afuera de
 * la composición. En iOS la pestaña no se destruye y su `@State` sigue ahí; acá cambiar de pestaña o girar el teléfono
 * descarta la pantalla, y la respuesta que llegaba después se perdía. Hay uno por modelo y cuenta (el `ModeloApp` vive lo
 * que el ViewModel; otra cuenta empieza de cero). Se usa desde el hilo principal.
 */
internal object EsperasDieta {
    private class DeLaCuenta(val cuenta: String?) {
        val comidasLibres = EstadoComidasLibres()
        val etiqueta = EscaneoEtiqueta()
    }

    private val porModelo = WeakHashMap<ModeloApp, DeLaCuenta>()

    @Synchronized
    private fun de(modelo: ModeloApp): DeLaCuenta {
        val cuenta = modelo.token
        porModelo[modelo]?.takeIf { it.cuenta == cuenta }?.let { return it }
        return DeLaCuenta(cuenta).also { porModelo[modelo] = it }
    }

    fun comidasLibres(modelo: ModeloApp): EstadoComidasLibres = de(modelo).comidasLibres

    fun etiqueta(modelo: ModeloApp): EscaneoEtiqueta = de(modelo).etiqueta
}

/**
 * "Escanear etiqueta" mientras la visión lee la foto: el formulario de "Alimento propio" aplica [resultado] cuando llega
 * (aunque se haya vuelto a armar en el medio) y lo consume. Cerrar la hoja lo olvida: una lectura que llega tarde no
 * prellena el próximo alimento.
 */
@Stable
class EscaneoEtiqueta {
    var escaneando by mutableStateOf(false)
        private set

    /** Lo que contestó la visión y todavía no se aplicó al formulario. */
    var resultado by mutableStateOf<Resultado<ValorJson>?>(null)
        private set

    private var vuelta = 0

    fun escanear(modelo: ModeloApp, alcance: CoroutineScope, jpeg: ByteArray) {
        if (escaneando) return
        val esta = ++vuelta
        escaneando = true
        resultado = null
        alcance.launch {
            val r = modelo.analizarFoto(jpeg, ClienteRpc.TipoVision.ETIQUETA)
            if (esta != vuelta) return@launch
            resultado = r
            escaneando = false
        }
    }

    fun consumir() {
        resultado = null
    }

    /** La hoja se cerró: lo que esté en camino ya no es de nadie. */
    fun olvidar() {
        vuelta++
        escaneando = false
        resultado = null
    }
}
