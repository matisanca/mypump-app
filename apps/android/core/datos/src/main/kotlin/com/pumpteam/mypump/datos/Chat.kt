package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SemanticaJs
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Una burbuja del hilo con Mati: la fila del servidor o una optimista que todavía no salió ("enviando…"). */
data class BurbujaChat(
    val id: String,
    val autor: String,
    val contenido: String,
    val leidoPorCliente: Boolean?,
    /** ISO, como lo manda el servidor (o la hora del teléfono para una optimista). */
    val createdAt: String,
    /** `_tmp`: escrita en el teléfono, todavía sin fila en el servidor. */
    val pendiente: Boolean = false,
    /** `_fallo`: la cola se rindió con este mensaje; se ofrece reintentar (el texto nunca se pierde). */
    val fallo: Boolean = false,
) {
    val esDelCoach: Boolean get() = autor == "coach"

    companion object {
        fun de(m: MensajeChat) = BurbujaChat(m.id, m.autor, m.contenido, m.leidoPorCliente, m.createdAt)
    }
}

/**
 * El hilo en memoria y `chatMerge` de la web (cliente.html:2268): sin repetir filas (el sondeo y la paginación se
 * solapan), ordenado por fecha, y cuando llega la fila real de un mensaje del cliente se van TODAS las optimistas con ese
 * texto (el servidor deduplica el mismo mensaje dentro de 2 minutos, mig 075, y una sobrante quedaría "enviando…" para
 * siempre). Inmutable: cada cambio devuelve un hilo nuevo, que es lo que publica el StateFlow.
 */
data class HiloChat(
    val mensajes: List<BurbujaChat> = emptyList(),
    /** El `created_at` del último mensaje real: desde ahí pregunta el sondeo. */
    val cursor: String? = null,
    val hayMas: Boolean = true,
) {
    data class Mezcla(val hilo: HiloChat, val entraron: Int)

    fun mezclar(filas: List<MensajeChat>): Mezcla {
        val lista = mensajes.toMutableList()
        val vistos = lista.mapTo(HashSet()) { it.id }
        var entraron = 0
        // Una fila que ya estaba puede venir con su "leído" (get_chat lo trae; chat_nuevos no): se actualiza, si no al
        // recargar el badge quedaba en 0 con el mensaje sin leer.
        for (f in filas) {
            val l = f.leidoPorCliente ?: continue
            if (f.id !in vistos) continue
            val i = lista.indexOfFirst { it.id == f.id }
            if (i >= 0) lista[i] = lista[i].copy(leidoPorCliente = l)
        }
        for (f in filas) {
            if (f.id in vistos) continue
            if (f.autor == "cliente") lista.removeAll { it.pendiente && it.autor == "cliente" && it.contenido == f.contenido }
            vistos += f.id
            lista += BurbujaChat.de(f)
            entraron += 1
        }
        val ordenados = ordenar(lista)
        return Mezcla(copy(mensajes = ordenados, cursor = ordenados.lastOrNull { !it.pendiente }?.createdAt ?: cursor), entraron)
    }

    fun agregarPendiente(b: BurbujaChat): HiloChat = copy(mensajes = ordenar(mensajes + b))

    /**
     * El servidor guardó un mensaje del cliente como la fila [id] (lo que devuelve `agregar_comentario`). Si esa fila ya está
     * en el hilo, una burbuja "enviando…" con ese texto ES esa fila: el servidor deduplica el mismo texto dentro de 2 minutos
     * (mig 075) y devuelve la que ya tenía, así que nunca llega una fila nueva que la saque y quedaba "enviando…" hasta
     * reiniciar (revisión del 15-oct, hallazgo 7). Si la fila todavía no llegó, la saca [mezclar] cuando llegue.
     */
    fun confirmar(contenido: String, id: String): HiloChat {
        if (mensajes.none { it.id == id && !it.pendiente }) return this
        val i = mensajes.indexOfFirst { it.pendiente && !it.fallo && it.autor == "cliente" && it.contenido == contenido }
        if (i < 0) return this
        return copy(mensajes = mensajes.toMutableList().also { it.removeAt(i) })
    }

    fun marcarFallido(contenido: String): HiloChat {
        val i = mensajes.indexOfFirst { it.pendiente && !it.fallo && it.contenido == contenido }
        if (i < 0) return this
        return copy(mensajes = mensajes.toMutableList().also { it[i] = it[i].copy(fallo = true) })
    }

    /** El hilo sin la marca de fallo en esa burbuja, y la burbuja (para reencolarla). */
    fun desmarcarFallido(id: String): Pair<HiloChat, BurbujaChat?> {
        val i = mensajes.indexOfFirst { it.id == id }
        if (i < 0) return this to null
        val b = mensajes[i].copy(fallo = false)
        return copy(mensajes = mensajes.toMutableList().also { it[i] = b }) to b
    }

    /** Todo lo del coach queda leído; dice además si había algo sin leer. */
    fun marcarLeidos(): Pair<HiloChat, Boolean> {
        val habia = mensajes.any { it.esDelCoach && it.leidoPorCliente == false }
        return copy(mensajes = mensajes.map { if (it.esDelCoach) it.copy(leidoPorCliente = true) else it }) to habia
    }

    val sinLeer: Int get() = mensajes.count { it.esDelCoach && it.leidoPorCliente == false }

    val primeroReal: BurbujaChat? get() = mensajes.firstOrNull { !it.pendiente }

    /** `sort((a, b) => new Date(a.created_at) - new Date(b.created_at))`: estable, como el de JS. */
    private fun ordenar(lista: List<BurbujaChat>): List<BurbujaChat> =
        SemanticaJs.ordenarEstable(lista) { a, b -> FechaIso.ms(a.createdAt).compareTo(FechaIso.ms(b.createdAt)) }
}

/**
 * Fechas ISO del servidor (`timestamptz` con microsegundos y zona) a milisegundos, como `new Date(iso)` de JS: lo
 * ilegible vale 0 (`new Date(undefined || 0)`).
 */
object FechaIso {
    private val ZONA_CORTA = Regex("[+-][0-9][0-9]$")
    private val FRACCION = Regex("\\.([0-9]+)")
    private val TEXTO = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).withZone(ZoneOffset.UTC)

    fun ms(iso: String): Double = instante(iso)?.toEpochMilli()?.toDouble() ?: 0.0

    fun instante(iso: String): Instant? {
        if (iso.isEmpty()) return null
        var s = iso.replace(' ', 'T')
        // Como JS (y como iOS): los milisegundos; el resto de los decimales se descarta.
        s = FRACCION.replace(s) { m -> "." + m.groupValues[1].take(3).padEnd(3, '0') }
        if (ZONA_CORTA.containsMatchIn(s)) s += ":00"
        return try {
            OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        } catch (_: Exception) {
            null
        }
    }

    /** Como `toISOString()`: UTC con tres decimales ("2026-10-13T12:00:00.000Z"). */
    fun texto(i: Instant): String = TEXTO.format(i)
}

/**
 * El chat con Mati (`ambito='general'`): páginas de 30 hacia atrás, sondeo con un cursor, envío por la cola con la burbuja
 * al instante, "no salió → Reintentar" si la cola se rinde, y marcar leído al abrir. Es sondeo y no Realtime a propósito:
 * la anon key es la misma para todos los clientes (CHA-06). Sin token es la demo ([demo]).
 */
class ModeloChat(
    private val cliente: ClienteRpc,
    /** null es la demo. */
    private val token: String?,
    private val outbox: Outbox?,
    private val alcance: CoroutineScope,
) {
    /**
     * La demo (`chatEsDemo` de la web, ACC-07): el hilo vacío para escribirle a Mati, y nada se carga, se manda, se sondea
     * ni se marca leído. La pantalla avisa que en la demo los mensajes no se envían.
     */
    val demo: Boolean = token == null

    // En la demo no hay nada más para traer (sin "Ver mensajes anteriores").
    private val _hilo = MutableStateFlow(HiloChat(hayMas = !demo))
    val hilo: StateFlow<HiloChat> = _hilo.asStateFlow()

    /** Badge del tab: lo del coach que llegó con el chat cerrado. */
    private val _noLeidos = MutableStateFlow(0)
    val noLeidos: StateFlow<Int> = _noLeidos.asStateFlow()

    private val _cargando = MutableStateFlow(false)
    val cargando: StateFlow<Boolean> = _cargando.asStateFlow()

    /** El hilo se trajo alguna vez: sin cursor, es que está vacío (y no que no se sabe). */
    @Volatile private var cargado = false
    val traido: Boolean get() = cargado

    /**
     * El hilo no se pudo traer nunca (sin red o el servicio caído). La pantalla lo dice en vez de mostrar el chat vacío,
     * que parecía que no había mensajes; la web muestra el vacío. Lo que se escribe igual sale por la cola (gemelo de iOS
     * a064dc0).
     */
    private val _sinTraer = MutableStateFlow(false)
    val sinTraer: StateFlow<Boolean> = _sinTraer.asStateFlow()

    /** Por qué no se pudo traer: sin red, o el servicio que no responde (el texto de la pantalla cambia). */
    @Volatile var sinTraerPorRed = true
        private set

    /**
     * Con el chat a la vista el sondeo va cada 15 s y marca leído lo nuevo; si no, cada 45 s y suma al badge. Al abrirlo
     * el sondeo vuelve a arrancar: si no, la espera de 45 s que estaba corriendo seguía (como la web, que cambia el
     * intervalo apenas se abre; revisión del 14-oct, hallazgo 11).
     */
    @Volatile var abierto = false
        set(v) {
            val antes = field
            field = v
            if (v != antes && sondeo != null) empezarSondeo()
        }

    private var sondeo: Job? = null
    internal val sondeoEnCurso: Job? get() = sondeo
    private val t get() = texto(token ?: "")   // la demo no llega acá: no toca la red

    /** `loadChat`: la última página, o una más hacia atrás. Sin red no toca nada. */
    suspend fun cargar(masViejos: Boolean = false) {
        if (demo || !_cargando.compareAndSet(expect = false, update = true)) return
        try {
            val antes = if (masViejos) _hilo.value.primeroReal?.let { texto(it.createdAt) } ?: ValorJson.Nulo else ValorJson.Nulo
            val r = cliente.filas(
                "mypump_get_chat",
                mapOf("p_token" to t, "p_antes" to antes, "p_limite" to numero(PAGINA)),
                MensajeChat::desde,
            )
            val filas = r.valorONull()
            if (filas == null) {
                if (!cargado) {
                    sinTraerPorRed = (r as? Resultado.Falla)?.error?.clase == ErrorRpc.Clase.RED
                    _sinTraer.value = true
                }
                return
            }
            cargado = true
            _sinTraer.value = false
            _hilo.update { h -> h.mezclar(filas).hilo.let { if (filas.size < PAGINA) it.copy(hayMas = false) else it } }
            recontar()
            if (abierto && !masViejos && _noLeidos.value > 0) marcarLeido()
        } finally {
            _cargando.value = false
        }
    }

    /** `chatPollTick`: lo nuevo desde el cursor. Lo que llega del coach por acá todavía no lo leyó (la RPC no trae el campo). */
    suspend fun sondear() {
        if (demo) return
        val desde = _hilo.value.cursor ?: return cargar()
        val filas = cliente.filas("mypump_chat_nuevos", mapOf("p_token" to t, "p_desde" to texto(desde)), MensajeChat::desde)
            .valorONull()
        if (filas.isNullOrEmpty()) return
        var entraron = 0
        _hilo.update { h -> h.mezclar(filas).also { entraron = it.entraron }.hilo }
        if (entraron == 0) return
        val delCoach = filas.count { it.esDelCoach }
        if (delCoach > 0) {
            // `mypump_chat_nuevos` no trae `leido_por_cliente`: sin forzar, `marcarLeido` no veía nada sin leer y Mati los
            // seguía viendo así (revisión del 14-oct, hallazgo 7; la web tiene el mismo agujero).
            if (abierto) marcarLeido(forzar = true) else _noLeidos.update { it + delCoach }
        }
    }

    /** Recalcula el badge sin bajarlo por debajo de lo que llegó por el sondeo (eso solo lo baja [marcarLeido]). */
    private fun recontar() {
        val sinLeer = _hilo.value.sinLeer
        _noLeidos.update { maxOf(it, sinLeer) }
    }

    /** `enviarChatMsg`: la burbuja aparece ya y el mensaje sale por la cola (sobrevive a cerrar la app sin señal). */
    suspend fun enviar(texto: String) {
        val contenido = TextoJs.recortar(texto)
        if (contenido.isEmpty() || demo) return
        val ahora = Instant.now()
        val b = BurbujaChat(
            id = "tmp_${ahora.toEpochMilli()}_${UUID.randomUUID().toString().take(5)}",
            autor = "cliente", contenido = contenido, leidoPorCliente = null, createdAt = FechaIso.texto(ahora), pendiente = true,
        )
        _hilo.update { it.agregarPendiente(b) }
        encolar(contenido)
        traerDespuesDeMandar()
    }

    /**
     * La burbuja deja de decir "enviando…" apenas sale (como la web, que sondea 250 ms después de un envío): esperar al
     * sondeo de 15-45 s hacía que el cliente creyera que no salió y lo mandara de nuevo.
     */
    private fun traerDespuesDeMandar() {
        alcance.launch {
            outbox?.drenar()
            delay(250)
            sondear()
        }
    }

    suspend fun reintentar(id: String) {
        var b: BurbujaChat? = null
        _hilo.update { h -> h.desmarcarFallido(id).also { b = it.second }.first }
        val burbuja = b ?: return
        encolar(burbuja.contenido)
        traerDespuesDeMandar()
    }

    /** La cola se rindió con un mensaje del chat. */
    fun marcarFallido(contenido: String) {
        _hilo.update { it.marcarFallido(contenido) }
    }

    /** La cola guardó un mensaje del chat como la fila [id] (también uno que el servidor deduplicó). */
    fun confirmar(contenido: String, id: String) {
        _hilo.update { it.confirmar(contenido, id) }
    }

    /**
     * `marcarChatLeido`: se decide por los mensajes (con el chat abierto el contador puede dar 0 y Mati los seguiría viendo
     * "sin leer").
     */
    suspend fun marcarLeido(forzar: Boolean = false) {
        if (demo) return
        var habia = false
        _hilo.update { h -> h.marcarLeidos().also { habia = it.second }.first }
        if (!habia && _noLeidos.value == 0 && !forzar) return
        _noLeidos.value = 0
        cliente.llamar("mypump_marcar_leidos_cliente", mapOf("p_token" to t, "p_ambito" to texto("general"), "p_referencia_id" to ValorJson.Nulo))
    }

    /** La espera entre consultas, en milisegundos. Los tests la cambian para ver los intervalos sin esperarlos. */
    internal var dormir: suspend (Long) -> Unit = { ms -> delay(ms) }

    /** Sondeo en cadena (nunca dos a la vez): 15 s abierto, 45 s cerrado. Se corta con la app en segundo plano. */
    fun empezarSondeo() {
        if (demo) return
        sondeo?.cancel()
        sondeo = alcance.launch {
            while (isActive) {
                dormir(if (abierto) 15_000L else 45_000L)
                sondear()
            }
        }
    }

    fun pararSondeo() {
        sondeo?.cancel()
        sondeo = null
    }

    private suspend fun encolar(contenido: String) {
        // La clave lleva el texto: dos mensajes distintos son dos ops; el mismo reencolado por un doble toque, una.
        val ms = System.currentTimeMillis()
        val payload = linkedMapOf<String, ValorJson>("contenido" to texto(contenido))
        // El último mensaje que el teléfono conoce, con la hora del servidor ("" con el hilo vacío): un reintento mira si ya
        // llegó contra eso y no contra el reloj del teléfono (`Escrituras.yaLlego`; hallazgo 7 del 15-oct).
        (_hilo.value.cursor ?: if (cargado) "" else null)?.let { payload["desde"] = texto(it) }
        outbox?.encolar("chat", ValorJson.Objeto(payload), "chat_${ms}_${contenido.take(40)}")
    }

    companion object {
        const val PAGINA = 30
    }
}
