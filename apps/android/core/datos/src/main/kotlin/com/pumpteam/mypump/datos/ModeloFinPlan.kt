package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FinPlan
import com.pumpteam.mypump.reglas.Recorrido
import com.pumpteam.mypump.reglas.RespuestasRecorrido
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** La palanca que se leyó por última vez, en la carpeta de la cuenta: sin red se sigue viendo lo guardado. Sin archivo, apagada. */
internal class PalancaEnDisco(private val disco: Disco?, private val archivo: String) {
    val prendida: Boolean get() = disco?.leer(archivo)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordar(prendida: Boolean) {
        if (prendida != this.prendida) disco?.guardar(archivo, ValorJson.Booleano(prendida))
    }
}

/**
 * Lo del teléfono de «Tu recorrido»: si la hoja ya se abrió sola, el id del pedido (se guarda ANTES de mandarlo: un reintento
 * va con el mismo y el servidor contesta `ya`) y lo que el alumno lleva escrito.
 */
data class LocalFinPlan(
    val abiertaSola: Boolean = false,
    val vistoAvisado: Boolean = false,
    val pedidoId: String? = null,
    val escrito: RespuestasRecorrido = RespuestasRecorrido(),
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("abiertaSola", ValorJson.Booleano(abiertaSola)); put("vistoAvisado", ValorJson.Booleano(vistoAvisado))
            pedidoId?.let { put("pedidoId", ValorJson.Texto(it)) }
            put("escrito", ValorJson.objeto("mejor" to ValorJson.Texto(escrito.mejor), "costo" to ValorJson.Texto(escrito.costo), "objetivo" to ValorJson.Texto(escrito.objetivo)))
        },
    )

    companion object {
        fun desde(v: ValorJson?): LocalFinPlan = LocalFinPlan(
            abiertaSola = v?.get("abiertaSola") == ValorJson.Booleano(true),
            vistoAvisado = v?.get("vistoAvisado") == ValorJson.Booleano(true),
            pedidoId = v?.get("pedidoId")?.comoTexto?.takeIf { it.isNotEmpty() },
            escrito = RespuestasRecorrido.desde(v?.get("escrito")),
        )
    }
}

/**
 * Fin de plan, «Tu recorrido» (2.3.0, palanca `fin_plan`; contrato `cola-b/CONTRATO_APP.md`, sección 1).
 *
 * - **Apagado no se ve.** Con la palanca apagada [ModeloApp] no llama a nada de esto y [recorrido] queda en null. PGRST202,
 *   404, `NULL` (token caído), `habilitado:false` o `visible:false`: null, y se borra la copia.
 * - **Un corte de red deja lo que ya se veía**: la última respuesta visible queda en `fin-plan.json`.
 * - **Pedir es idempotente**: el id del pedido se guarda en disco antes de mandarlo y un reintento va con el mismo.
 * - Quién lo ve lo decide el servidor: acá no hay fechas.
 */
class ModeloFinPlan(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    private val nuevoId: () -> String = { UUID.randomUUID().toString() },
) {
    enum class Salida {
        OK,
        /** Sin red o un error del servidor: «No se pudo enviar. Probá de nuevo.» y el botón vuelve. */
        ERROR,
        /** `apagado` o `no_disponible`: se cierra la hoja y deja de verse. */
        YA_NO,
        /** Ya había un pedido saliendo (dos toques): no se manda otro. */
        OCUPADO,
    }

    private val palanca = PalancaEnDisco(disco, ARCHIVO_PALANCA)
    val palancaRecordada: Boolean get() = palanca.prendida

    private val _recorrido = MutableStateFlow(
        if (palanca.prendida) disco?.leer(ARCHIVO)?.let { (FinPlan.leer(ValorJson.desde(it)) as? FinPlan.Lectura.Visible)?.recorrido } else null,
    )

    /** Lo que muestran la tarjeta, Mis datos y la hoja. null: no se ve nada. */
    val recorrido: StateFlow<Recorrido?> = _recorrido.asStateFlow()

    private val _local = MutableStateFlow(LocalFinPlan.desde(disco?.leer(ARCHIVO_LOCAL)?.let { ValorJson.desde(it) }))
    val local: StateFlow<LocalFinPlan> = _local.asStateFlow()

    private val _enviando = MutableStateFlow(false)
    val enviando: StateFlow<Boolean> = _enviando.asStateFlow()

    private val pidiendo = Mutex()

    /** La hoja se abre sola una vez: la primera vez que llega visible y sin pedir. */
    val seAbreSola: Boolean get() = FinPlan.seAbreSola(_recorrido.value, _local.value.abiertaSola)

    /** La palanca `fin_plan` recién leída. Apagada: no queda nada a la vista ni la copia. */
    fun usarPalanca(prendida: Boolean) {
        palanca.recordar(prendida)
        if (!prendida) apagar()
    }

    /** Deja de verse, y la copia se va: lo que se vuelva a mostrar tiene que decirlo el servidor. Lo del teléfono queda. */
    fun apagar() {
        _recorrido.value = null
        disco?.borrar(ARCHIVO)
    }

    private fun p() = mapOf("p_token" to ValorJson.Texto(token))

    /** `get`: al cargar la cuenta y al volver a primer plano. Solo con la palanca prendida (lo decide [ModeloApp]). */
    suspend fun refrescar() {
        when (val r = cliente.llamar(RPC_GET, p())) {
            is Resultado.Ok -> when (val l = FinPlan.leer(r.valor)) {
                is FinPlan.Lectura.Visible -> {
                    _recorrido.value = l.recorrido
                    disco?.guardar(ARCHIVO, r.valor)
                    // Ya pidió (acá o en otro teléfono): no queda pedido a medias ni texto por mandar.
                    if (l.recorrido.estado != Recorrido.Estado.PUBLICADO && (_local.value.pedidoId != null || !_local.value.escrito.vacias)) {
                        guardar(_local.value.copy(pedidoId = null, escrito = RespuestasRecorrido()))
                    }
                }
                FinPlan.Lectura.NoVisible -> {
                    apagar()
                    // Terminó este recorrido: el próximo que publique Mati es otro y se vuelve a abrir solo una vez.
                    // (`NULL` del token caído no pasa por acá: no dice nada del recorrido.)
                    if (r.valor["habilitado"] == ValorJson.Booleano(true) && r.valor["visible"] == ValorJson.Booleano(false) && _local.value != LocalFinPlan()) {
                        guardar(LocalFinPlan())
                    }
                }
                FinPlan.Lectura.Apagado -> apagar()
            }
            // La función no está (PGRST202, 404) o el servidor dijo que no: no se ve nada. Un corte deja lo que había.
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) apagar()
        }
    }

    /** Al abrir la hoja: ya no se abre sola, y el servidor se entera una vez (si falla no importa: se prueba la próxima). */
    suspend fun alAbrirLaHoja() {
        if (_recorrido.value == null) return
        if (!_local.value.abiertaSola) guardar(_local.value.copy(abiertaSola = true))
        if (_local.value.vistoAvisado) return
        val r = cliente.llamar(RPC_VISTO, p())
        if (r is Resultado.Ok && r.valor["ok"] == ValorJson.Booleano(true)) guardar(_local.value.copy(vistoAvisado = true))
    }

    /** Se abrió sola (o se decidió no abrirla porque ya la vio por la tarjeta): no vuelve a abrirse sola. */
    fun marcarAbiertaSola() {
        if (!_local.value.abiertaSola) guardar(_local.value.copy(abiertaSola = true))
    }

    /** Lo que va escribiendo, con el tope de 500, guardado en disco mientras tanto. */
    fun escribir(clave: String, texto: String) {
        val nuevo = _local.value.escrito.con(clave, texto)
        if (nuevo != _local.value.escrito) guardar(_local.value.copy(escrito = nuevo))
    }

    /** «Agendar con Mati». Nunca dos a la vez; un reintento después de un corte va con el mismo id. */
    suspend fun pedir(): Salida {
        val r0 = _recorrido.value ?: return Salida.YA_NO
        if (r0.estado != Recorrido.Estado.PUBLICADO) return Salida.OK
        if (!pidiendo.tryLock()) return Salida.OCUPADO
        _enviando.value = true
        try {
            val id = _local.value.pedidoId ?: nuevoId().also { nuevo ->
                // Antes de mandar: si no queda escrito, no se manda (un corte a mitad dejaría un pedido sin id que repetir).
                if (!guardar(_local.value.copy(pedidoId = nuevo)) && disco != null) return Salida.ERROR
            }
            val escrito = _local.value.escrito
            val r = cliente.llamar(RPC_PEDIR, p() + mapOf("p_id" to ValorJson.Texto(id), "p_respuestas" to escrito.aValor()))
            return when (r) {
                is Resultado.Falla -> Salida.ERROR   // red, 5xx o 22023: el id queda para el reintento
                is Resultado.Ok -> {
                    val j = r.valor
                    if (j["ok"] == ValorJson.Booleano(true)) {
                        val estado = FinPlan.estado(j["estado"]?.comoTexto)?.takeIf { it != Recorrido.Estado.PUBLICADO } ?: Recorrido.Estado.PEDIDO
                        _recorrido.value = r0.copy(estado = estado, respuestas = RespuestasRecorrido.desde(escrito.aValor()))
                        guardar(_local.value.copy(pedidoId = null, escrito = RespuestasRecorrido()))
                        refrescar()
                        Salida.OK
                    } else when (j["error"]?.comoTexto) {
                        "apagado", "no_disponible" -> {
                            guardar(_local.value.copy(pedidoId = null))
                            refrescar()
                            // Si el `get` no llegó, igual deja de verse: el servidor ya dijo que no.
                            if (_recorrido.value?.estado == Recorrido.Estado.PUBLICADO) apagar()
                            Salida.YA_NO
                        }
                        else -> Salida.ERROR   // `NULL` (token caído) u otro error: el botón vuelve
                    }
                }
            }
        } finally {
            _enviando.value = false
            pidiendo.unlock()
        }
    }

    private fun guardar(l: LocalFinPlan): Boolean {
        _local.value = l
        return disco?.guardar(ARCHIVO_LOCAL, l.aValor()) ?: false
    }

    companion object {
        const val RPC_GET = "mypump_fin_plan_get"
        const val RPC_VISTO = "mypump_fin_plan_visto"
        const val RPC_PEDIR = "mypump_fin_plan_pedir"
        internal const val ARCHIVO = "fin-plan.json"
        internal const val ARCHIVO_LOCAL = "fin-plan-local.json"
        internal const val ARCHIVO_PALANCA = "fin-plan-palanca.json"
    }
}
