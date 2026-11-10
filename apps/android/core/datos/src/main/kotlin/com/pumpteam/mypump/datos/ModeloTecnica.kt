package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EnvioTecnica
import com.pumpteam.mypump.reglas.EstadoTecnica
import com.pumpteam.mypump.reglas.Tecnica
import com.pumpteam.mypump.reglas.TopesTecnica
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.pow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json

/** El video que espera subir. Uno por vez: el contrato no deja abrir otro mientras haya uno en curso. */
data class PendienteTecnica(val id: String, val envioId: String?, val slug: String, val nombre: String, val nota: String, val consentimiento: String) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("id", ValorJson.Texto(id)); put("slug", ValorJson.Texto(slug)); put("nombre", ValorJson.Texto(nombre))
            put("nota", ValorJson.Texto(nota)); put("consentimiento", ValorJson.Texto(consentimiento))
            envioId?.let { put("envioId", ValorJson.Texto(it)) }
        },
    )

    companion object {
        const val CARPETA = "tecnica-videos"

        fun desde(v: ValorJson?): PendienteTecnica? {
            v ?: return null
            return PendienteTecnica(
                v["id"]?.comoTexto ?: return null, v["envioId"]?.comoTexto, v["slug"]?.comoTexto ?: "", v["nombre"]?.comoTexto ?: "",
                v["nota"]?.comoTexto ?: "", v["consentimiento"]?.comoTexto ?: return null,
            )
        }
    }
}

/** Lo que vive en disco: el aviso aceptado y el video en camino, juntos en un archivo que se escribe de una vez. */
data class ColaTecnica(val avisoVersion: String? = null, val pendiente: PendienteTecnica? = null) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            avisoVersion?.let { put("avisoVersion", ValorJson.Texto(it)) }
            pendiente?.let { put("pendiente", it.aValor()) }
        },
    )

    companion object {
        const val ARCHIVO = "tecnica-cola.json"

        fun leer(disco: Disco): ColaTecnica {
            val v = disco.leer(ARCHIVO)?.let { ValorJson.desde(it) } ?: return ColaTecnica()
            return ColaTecnica(v["avisoVersion"]?.comoTexto, PendienteTecnica.desde(v["pendiente"]))
        }
    }
}

/**
 * Técnica por video. Mismo criterio de cola que [ModeloGimnasio]: en disco, sobrevive a cerrar la app y a quedarse sin señal, un
 * 5xx o 429 no gasta el video y lo demás de 4xx es definitivo. El video se sube desde su archivo, nunca entero en memoria. Con la
 * palanca `tecnica_video` apagada [ModeloApp] no llama a nada de esto: [estado] queda en null. Gemelo de ModeloTecnica.swift.
 */
class ModeloTecnica(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    /** Espera entre reintentos, en milisegundos (en las pruebas, nada). */
    private val esperar: suspend (Long) -> Unit = { delay(it) },
    private val lanzar: (suspend () -> Unit) -> Unit = {},
) {
    enum class Salida { OK, SIN_SENAL, OCUPADO, ERROR }
    enum class Encolar { GUARDADO, OCUPADO, NO_SE_GUARDO }

    sealed interface Aviso {
        data class Rechazo(val rechazo: Tecnica.Rechazo) : Aviso
        data object EnCurso : Aviso
        data object TopeSemanal : Aviso
        data object Error : Aviso
    }

    private val _estado = MutableStateFlow<EstadoTecnica?>(null)
    /** null: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada. */
    val estado: StateFlow<EstadoTecnica?> = _estado.asStateFlow()
    private val _subiendo = MutableStateFlow(false)
    /** Hay un pedido en vuelo con este video (abrir el envío o subirlo). */
    val subiendo: StateFlow<Boolean> = _subiendo.asStateFlow()
    private val _aviso = MutableStateFlow<Aviso?>(null)
    val aviso: StateFlow<Aviso?> = _aviso.asStateFlow()
    private val _cola = MutableStateFlow(disco?.let { ColaTecnica.leer(it) } ?: ColaTecnica())
    val cola: StateFlow<ColaTecnica> = _cola.asStateFlow()

    private val drenando = Mutex()
    private val reintentoProgramado = AtomicBoolean(false)
    @Volatile private var reintentosDeFondo = 0

    init {
        // Un cierre entre el archivo y el índice deja un video que nadie sube ni borra.
        val vivo = _cola.value.pendiente?.let { "${it.id}.mp4" }
        disco?.archivo(PendienteTecnica.CARPETA)?.listFiles()?.filter { it.name != vivo }?.forEach { it.delete() }
    }

    /** La palanca `tecnica_video` que se leyó por última vez: prendida, un video en la cola sigue subiendo aunque se arranque sin red. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    // ── Lo que lee la pantalla ──

    val pendiente: PendienteTecnica? get() = _cola.value.pendiente
    val habilitado: Boolean get() = _estado.value != null
    val envios: List<EnvioTecnica> get() = _estado.value?.visibles ?: emptyList()
    val topes: TopesTecnica get() = _estado.value?.topes ?: TopesTecnica()

    /** El aviso de terceros, una sola vez: si el servidor no lo tiene aceptado y en este teléfono no se aceptó esta versión. */
    val necesitaAviso: Boolean get() = _estado.value?.let { !it.consentimientoAceptado && _cola.value.avisoVersion != it.consentimientoVersion } ?: false

    /** Se puede mandar otro: nada en camino y nada esperando la devolución. */
    val puedeMandar: Boolean get() = _estado.value != null && pendiente == null && _estado.value?.enRevision == null

    // ── Servidor ──

    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_tecnica_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) {
                    _estado.value = null
                    return
                }
                val e = EstadoTecnica.desde(r.valor)
                if (e == null) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                    return
                }
                _estado.value = e
                disco?.guardar(ARCHIVO_ESTADO, r.valor)
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                } else if (_estado.value == null) {
                    // Sin red, lo último que se supo: la devolución se puede releer en el gimnasio y la cola sigue viva.
                    disco?.leer(ARCHIVO_ESTADO)?.let { EstadoTecnica.desde(ValorJson.desde(it)) }?.let { _estado.value = it }
                }
            }
        }
    }

    fun apagar() {
        _estado.value = null
    }

    fun aceptarAviso() {
        val e = _estado.value ?: return
        _cola.update { it.copy(avisoVersion = e.consentimientoVersion) }
        guardar()
    }

    fun limpiarAviso() {
        _aviso.value = null
    }

    // ── Cola ──

    /** Mueve el video ya preparado a la cola. Después hay que drenar. */
    fun encolar(archivo: File, slug: String, nombre: String, nota: String): Encolar {
        val e = _estado.value ?: return Encolar.OCUPADO
        if (pendiente != null || e.enRevision != null || necesitaAviso) return Encolar.OCUPADO
        val d = disco ?: return Encolar.NO_SE_GUARDO
        val id = UUID.randomUUID().toString()
        val destino = d.archivo("${PendienteTecnica.CARPETA}/$id.mp4")
        try {
            destino.parentFile?.mkdirs()
            if (!archivo.renameTo(destino)) {
                archivo.copyTo(destino, overwrite = true)
                archivo.delete()
            }
        } catch (_: Exception) {
            destino.delete()
            return Encolar.NO_SE_GUARDO
        }
        _cola.update { it.copy(pendiente = PendienteTecnica(id, null, slug.take(Tecnica.MAX_NOMBRE), nombre.take(Tecnica.MAX_NOMBRE), Tecnica.nota(nota), e.consentimientoVersion)) }
        if (!guardar()) {
            _cola.update { it.copy(pendiente = null) }
            destino.delete()
            return Encolar.NO_SE_GUARDO
        }
        _aviso.value = null
        return Encolar.GUARDADO
    }

    fun drenarEnFondo() {
        lanzar { drenar() }
    }

    private enum class Paso { SEGUIR, FIN, REINTENTAR, RED }

    /** Una pasada a la vez. Red: corta y queda para después. 5xx o 429: espera y reintenta, y a la tercera seguida deja de insistir un rato. */
    suspend fun drenar() {
        if (_estado.value == null || !drenando.tryLock()) return
        try {
            var seguidas = 0
            while (true) {
                val p = pendiente ?: break
                if (_estado.value == null) break
                _subiendo.value = true
                val r = try {
                    if (p.envioId == null) abrir(p) else subir(p)
                } finally {
                    _subiendo.value = false
                }
                when (r) {
                    Paso.SEGUIR -> seguidas = 0
                    Paso.FIN -> break
                    Paso.RED -> {
                        programarReintento()
                        break
                    }
                    Paso.REINTENTAR -> {
                        seguidas++
                        if (seguidas >= MAX_INTENTOS_SEGUIDOS) {
                            programarReintento()
                            break
                        }
                        esperar(2.0.pow(seguidas).toLong() * 1000)
                    }
                }
            }
        } finally {
            drenando.unlock()
        }
    }

    private fun programarReintento() {
        if (reintentosDeFondo >= MAX_REINTENTOS_DE_FONDO || !reintentoProgramado.compareAndSet(false, true)) return
        reintentosDeFondo++
        lanzar {
            esperar(60_000)
            reintentoProgramado.set(false)
            drenar()
        }
    }

    /** `nuevo`: si ya había un borrador devuelve ese, así que repetirlo después de un corte no duplica. */
    private suspend fun abrir(p: PendienteTecnica): Paso {
        val r = cliente.llamar(
            "mypump_tecnica_nuevo",
            mapOf(
                "p_token" to ValorJson.Texto(token), "p_ejercicio_slug" to ValorJson.Texto(p.slug), "p_ejercicio_nombre" to ValorJson.Texto(p.nombre),
                "p_nota" to ValorJson.Texto(p.nota), "p_consentimiento" to ValorJson.Texto(p.consentimiento),
            ),
        )
        when (r) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) return Paso.FIN   // token caído: queda guardado para el link nuevo
                val id = r.valor["id"]?.comoTexto
                if (r.valor["ok"] == ValorJson.Booleano(true) && !id.isNullOrEmpty()) {
                    _cola.update { it.copy(pendiente = it.pendiente?.copy(envioId = id)) }
                    guardar()
                    return Paso.SEGUIR
                }
                when (r.valor["error"]?.comoTexto) {
                    "reintentar" -> return Paso.REINTENTAR
                    "no_habilitado" -> apagar()
                    "en_curso" -> soltar(p, Aviso.EnCurso)
                    "tope_semanal" -> soltar(p, Aviso.TopeSemanal)
                    "consentimiento" -> {
                        _cola.update { it.copy(avisoVersion = null) }
                        soltar(p, Aviso.Error)
                    }
                    else -> soltar(p, Aviso.Error)
                }
                return Paso.FIN
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente) {
                    apagar()
                    return Paso.FIN
                }
                if (r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    soltar(p, Aviso.Error)
                    return Paso.FIN
                }
                return if (r.error.clase == ErrorRpc.Clase.RED) Paso.RED else Paso.REINTENTAR
            }
        }
    }

    private suspend fun subir(p: PendienteTecnica): Paso {
        val archivo = url(p.id)
        val id = p.envioId
        if (id == null || !archivo.isFile || archivo.length() <= 0) {
            soltar(p, Aviso.Error)
            return Paso.FIN
        }
        val pedido = Pedido(
            url = "${cliente.config.vision}/tecnica/upload", metodo = "POST",
            cabeceras = mapOf("Content-Type" to "video/mp4", "x-tecnica-token" to token, "x-tecnica-id" to id),
            cuerpo = null, esperaMs = ESPERA_SUBIDA_MS, archivo = archivo,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Paso.RED
        }
        val j = parsear(r.cuerpo)
        val s = Tecnica.clasificarSubida(r.status, j?.get("ok") == ValorJson.Booleano(true), j?.get("error")?.comoTexto)
        return when (s.accion) {
            Tecnica.Accion.OK -> {
                quitarLocal(p)
                reintentosDeFondo = 0
                marcarEnviado(id, p)
                refrescar()
                Paso.FIN
            }
            Tecnica.Accion.REINTENTAR -> Paso.REINTENTAR
            Tecnica.Accion.GUARDAR -> Paso.FIN
            Tecnica.Accion.DESCARTAR -> {
                soltar(p, Aviso.Rechazo(s.rechazo ?: Tecnica.Rechazo.OTRO))
                Paso.FIN
            }
        }
    }

    /** Hasta que llegue el `get`, para que la lista ya lo muestre recibido. */
    private fun marcarEnviado(id: String, p: PendienteTecnica) {
        val e = _estado.value ?: return
        val ya = e.envios.any { it.id == id }
        val lista = if (ya) {
            e.envios.map { if (it.id == id) it.copy(estado = EnvioTecnica.Estado.ENVIADO, tieneVideo = true) else it }
        } else {
            listOf(EnvioTecnica(id, EnvioTecnica.Estado.ENVIADO, p.slug, p.nombre, p.nota.ifEmpty { null }, tieneVideo = true)) + e.envios
        }
        _estado.value = e.copy(envios = lista)
    }

    private fun quitarLocal(p: PendienteTecnica) {
        _cola.update { it.copy(pendiente = null) }
        guardar()
        url(p.id).delete()
    }

    /** Definitivo: se avisa, se saca el video y se cierra el borrador del servidor si llegó a abrirse. */
    private suspend fun soltar(p: PendienteTecnica, a: Aviso) {
        quitarLocal(p)
        _aviso.value = a
        p.envioId?.let { cancelarEnServidor(it) }
        refrescar()
    }

    private suspend fun cancelarEnServidor(id: String) {
        cliente.llamar("mypump_tecnica_cancelar", mapOf("p_token" to ValorJson.Texto(token), "p_id" to ValorJson.Texto(id)))
    }

    /** El alumno se arrepiente antes de que suba. Mientras hay un pedido en vuelo no se puede. */
    suspend fun cancelarPendiente(): Boolean {
        val p = pendiente
        if (_subiendo.value || p == null) return false
        quitarLocal(p)
        _aviso.value = null
        p.envioId?.let { cancelarEnServidor(it) }
        return true
    }

    // ── El video ya subido ──

    /** La URL firmada de su propio video. null: no se pudo. */
    suspend fun urlVideo(id: String): String? {
        val r = postVision("tecnica/url", ValorJson.objeto("token" to ValorJson.Texto(token), "id" to ValorJson.Texto(id))) ?: return null
        if (r.second?.get("ok") != ValorJson.Booleano(true)) return null
        return r.second?.get("url")?.comoTexto
    }

    suspend fun sacarVideo(id: String): Salida {
        val r = postVision("tecnica/borrar", ValorJson.objeto("token" to ValorJson.Texto(token), "id" to ValorJson.Texto(id))) ?: return Salida.SIN_SENAL
        if (r.first == 409) return Salida.OCUPADO
        if (r.first !in 200..299 || r.second?.get("ok") != ValorJson.Booleano(true)) return Salida.ERROR
        _estado.value?.let { e -> _estado.value = e.copy(envios = e.envios.map { if (it.id == id) it.copy(tieneVideo = false) else it }) }
        refrescar()
        return Salida.OK
    }

    private suspend fun postVision(ruta: String, cuerpo: ValorJson): Pair<Int, ValorJson?>? {
        val pedido = Pedido(
            url = "${cliente.config.vision}/$ruta", metodo = "POST", cabeceras = mapOf("Content-Type" to "application/json"),
            cuerpo = cuerpo.serializar().toByteArray(), esperaMs = 30_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return null
        }
        return r.status to parsear(r.cuerpo)
    }

    private fun parsear(b: ByteArray): ValorJson? = try {
        ValorJson.desde(Json.parseToJsonElement(b.toString(Charsets.UTF_8)))
    } catch (_: Exception) {
        null
    }

    // ── Disco ──

    internal fun url(id: String): File = disco?.archivo("${PendienteTecnica.CARPETA}/$id.mp4") ?: File(System.getProperty("java.io.tmpdir"), "$id.mp4")

    private fun guardar(): Boolean = disco?.guardar(ColaTecnica.ARCHIVO, _cola.value.aValor()) ?: false

    /** El video que quedó en la carpeta de otro link de la misma persona. El envío sigue siendo suyo. */
    internal fun adoptar(otro: PendienteTecnica, desde: Disco): Boolean {
        val d = disco ?: return false
        if (pendiente != null) return false
        val origen = desde.archivo("${PendienteTecnica.CARPETA}/${otro.id}.mp4")
        val destino = d.archivo("${PendienteTecnica.CARPETA}/${otro.id}.mp4")
        try {
            destino.parentFile?.mkdirs()
            if (!origen.renameTo(destino)) {
                origen.copyTo(destino, overwrite = true)
                origen.delete()
            }
        } catch (_: Exception) {
            return false
        }
        _cola.update { it.copy(pendiente = otro) }
        return guardar()
    }

    companion object {
        private const val ARCHIVO_ESTADO = "tecnica-estado.json"
        private const val ARCHIVO_PALANCA = "tecnica-palanca.json"
        private const val MAX_INTENTOS_SEGUIDOS = 3
        private const val MAX_REINTENTOS_DE_FONDO = 5

        /** El servidor corta el cuerpo a los 240 s: un poco más y el corte lo dice él. */
        private const val ESPERA_SUBIDA_MS = 300_000L
    }
}
