package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.DevolucionSemanal
import com.pumpteam.mypump.reglas.EstadoDevolucion
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * «Devolución de Mati» en Revisión. Solo lee: `mypump_devolucion_get` con el token. Con la palanca `devolucion_semanal`
 * apagada `ModeloApp` no llama a nada de esto y `estado` queda en null. Sin red muestra lo último que se supo.
 * Gemelo de ModeloDevolucion.swift.
 */
class ModeloDevolucion(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
) {
    private val _estado = MutableStateFlow<EstadoDevolucion?>(null)
    /** null: apagada, sin el servidor nuevo o sin habilitar. No se muestra nada. */
    val estado: StateFlow<EstadoDevolucion?> = _estado.asStateFlow()

    val ultima: DevolucionSemanal? get() = _estado.value?.ultima
    val anteriores: List<DevolucionSemanal> get() = _estado.value?.anteriores ?: emptyList()

    /** La palanca leída la última vez: prendida, sin red se sigue viendo la última devolución guardada. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_devolucion_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                // NULL (token caído) o `habilitado: false`: se apaga y se olvida lo guardado.
                val e = EstadoDevolucion.desde(r.valor) ?: return apagar()
                _estado.value = e
                disco?.guardar(ARCHIVO, r.valor)
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                } else if (_estado.value == null) {
                    disco?.leer(ARCHIVO)?.let { EstadoDevolucion.desde(ValorJson.desde(it)) }?.let { _estado.value = it }
                }
            }
        }
    }

    /** Palanca apagada o cuenta que se va: no queda nada en pantalla ni en disco. */
    fun apagar() {
        _estado.value = null
        disco?.borrar(ARCHIVO)
    }

    companion object {
        const val ARCHIVO = "devolucion-estado.json"
        const val ARCHIVO_PALANCA = "devolucion-palanca.json"
    }
}
