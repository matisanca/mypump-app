package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Compras
import com.pumpteam.mypump.reglas.ComprasPais
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Compras por país, «Dónde comprarlo» (2.3.0, palanca `compras_pais`; contrato `cola-b/CONTRATO_APP.md`, sección 2).
 * `mypump_compras_get(p_token)`, de solo lectura, junto con la suplementación (misma carga) y solo si hay suplementación.
 *
 * - **Apagado no se ve.** Con la palanca apagada [ModeloApp] no llama a nada y [compras] queda en null. PGRST202, 404,
 *   `NULL` o `habilitado:false`: null, y se borra la copia. `items` vacío: no se muestra nada (ni un cartel).
 * - **Un corte de red deja lo que ya se veía**: la última respuesta queda en `compras.json`.
 */
class ModeloCompras(private val cliente: ClienteRpc, private val token: String, private val disco: Disco?) {
    private val palanca = PalancaEnDisco(disco, ARCHIVO_PALANCA)
    val palancaRecordada: Boolean get() = palanca.prendida

    private val _compras = MutableStateFlow(if (palanca.prendida) disco?.leer(ARCHIVO)?.let { Compras.leer(ValorJson.desde(it)) } else null)

    /** null o sin ítems: la pestaña Suplementación es la de siempre. */
    val compras: StateFlow<ComprasPais?> = _compras.asStateFlow()

    fun usarPalanca(prendida: Boolean) {
        palanca.recordar(prendida)
        if (!prendida) apagar()
    }

    fun apagar() {
        _compras.value = null
        disco?.borrar(ARCHIVO)
    }

    suspend fun refrescar() {
        when (val r = cliente.llamar(RPC, mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                val c = Compras.leer(r.valor)
                if (c == null) {
                    apagar()
                } else {
                    _compras.value = c
                    disco?.guardar(ARCHIVO, r.valor)
                }
            }
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) apagar()
        }
    }

    companion object {
        const val RPC = "mypump_compras_get"
        internal const val ARCHIVO = "compras.json"
        internal const val ARCHIVO_PALANCA = "compras-palanca.json"
    }
}
