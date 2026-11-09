package com.pumpteam.mypump.dieta

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
 * "Escanear etiqueta" mientras la visión lee la foto: la lectura es de un formulario de "Alimento propio" ([dueno], un id que
 * sobrevive a la rotación). Ese formulario aplica [resultado] cuando llega (aunque se haya vuelto a armar en el medio) y lo
 * consume; otro formulario no la ve ni queda bloqueado por ella, y si escanea, la de antes ya no es de nadie.
 */
@Stable
class EscaneoEtiqueta {
    private var dueno by mutableStateOf<String?>(null)
    private var enCurso by mutableStateOf(false)
    private var respuesta by mutableStateOf<Resultado<ValorJson>?>(null)
    private var vuelta = 0

    fun escaneando(dueno: String): Boolean = enCurso && this.dueno == dueno

    /** Lo que contestó la visión para ese formulario y todavía no se aplicó. */
    fun resultado(dueno: String): Resultado<ValorJson>? = respuesta.takeIf { this.dueno == dueno }

    fun escanear(dueno: String, alcance: CoroutineScope, leer: suspend () -> Resultado<ValorJson>) {
        if (escaneando(dueno)) return
        val esta = ++vuelta
        this.dueno = dueno
        enCurso = true
        respuesta = null
        alcance.launch {
            val r = leer()
            if (esta != vuelta) return@launch
            respuesta = r
            enCurso = false
        }
    }

    fun consumir(dueno: String) {
        if (this.dueno == dueno) respuesta = null
    }

    /** La hoja se cerró: lo que esté en camino ya no es de nadie. */
    fun olvidar() {
        vuelta++
        dueno = null
        enCurso = false
        respuesta = null
    }
}
