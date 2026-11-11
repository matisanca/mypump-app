package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasListaPrevia
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * La lista previa a la videollamada de comienzo (2.3.0, palanca `lista_previa`; gemelo de ModeloListaPrevia.swift). Solo
 * lee: `mypump_lista_previa` con el token, al abrir Entreno, al volver al frente y cuando cambia la guía o la agenda (como
 * mucho un pedido cada 60 s; sin sondeo propio). Con la palanca apagada no llama a nada y [vista] queda en null.
 */
class ModeloListaPrevia private constructor(
    private val cliente: ClienteRpc?,
    private val token: String,
    private val disco: Disco?,
    private val reloj: () -> Instant,
    muestra: ValorJson?,
) {
    constructor(cliente: ClienteRpc, token: String, disco: Disco?, reloj: () -> Instant = Instant::now) : this(cliente, token, disco, reloj, null)

    private val _vista = MutableStateFlow(muestra?.let(ReglasListaPrevia::vista))
    /** null: apagada, inactiva, sin el servidor nuevo o sin ítems. No se muestra nada. */
    val vista: StateFlow<ReglasListaPrevia.Vista?> = _vista.asStateFlow()

    /** La demo: la lista fija de `historial.json`, que nunca toca la red. */
    val demo: Boolean get() = cliente == null

    private var ultimoPedido: Instant? = null
    private var pidiendo = false

    /** La palanca leída la última vez (por cuenta): apagada, ni una llamada. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
        if (!prendida) apagar()
    }

    /** Al abrir Entreno, al volver al frente o cuando cambió la guía o la agenda. Nunca más de un pedido cada 60 s. */
    suspend fun refrescar() {
        val c = cliente ?: return
        if (pidiendo || !palancaRecordada) return
        val ahora = reloj()
        ultimoPedido?.let { if (Duration.between(it, ahora) < ESPERA_MINIMA) return }
        ultimoPedido = ahora
        pidiendo = true
        try {
            when (val r = c.llamar("mypump_lista_previa", mapOf("p_token" to texto(token)))) {
                is Resultado.Ok -> {
                    val v = ReglasListaPrevia.vista(r.valor)
                    _vista.value = v
                    if (v != null) disco?.guardar(ARCHIVO, r.valor) else disco?.borrar(ARCHIVO)
                }
                is Resultado.Falla -> {
                    if (r.error.funcionInexistente || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                        apagar()
                    } else if (_vista.value == null) {
                        // Sin red: lo último que se supo, si todavía no hay nada en pantalla.
                        disco?.leer(ARCHIVO)?.let { ReglasListaPrevia.vista(ValorJson.desde(it)) }?.let { _vista.value = it }
                    }
                }
            }
        } finally {
            pidiendo = false
        }
    }

    /** Palanca apagada o cuenta que se va: no queda nada en pantalla ni en disco. */
    fun apagar() {
        if (cliente == null) return
        _vista.value = null
        ultimoPedido = null
        disco?.borrar(ARCHIVO)
    }

    companion object {
        const val ARCHIVO = "lista-previa.json"
        const val ARCHIVO_PALANCA = "lista-previa-palanca.json"
        val ESPERA_MINIMA: Duration = Duration.ofSeconds(60)

        /** La de la demo (`historial.json → lista_previa`): fija, sin red ni disco. */
        fun demo(muestra: ValorJson?): ModeloListaPrevia = ModeloListaPrevia(null, "", null, Instant::now, muestra)
    }
}
