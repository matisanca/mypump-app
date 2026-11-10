package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CargaGimnasio
import com.pumpteam.mypump.reglas.EstadoGimnasio
import com.pumpteam.mypump.reglas.FotoGimnasio
import com.pumpteam.mypump.reglas.Gimnasio
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json

/** Una foto que espera subir. El JPEG va en su propio archivo (`gimnasio-fotos/<id>.jpg`) y acá solo el índice. */
data class PendienteGimnasio(val id: String, val gimnasioId: String, val zona: String, val pregunta: String? = null) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("id", ValorJson.Texto(id)); put("gimnasioId", ValorJson.Texto(gimnasioId)); put("zona", ValorJson.Texto(zona))
            pregunta?.let { put("pregunta", ValorJson.Texto(it)) }
        },
    )

    companion object {
        const val ARCHIVO = "gimnasio-cola.json"
        const val CARPETA = "gimnasio-fotos"

        fun desde(v: ValorJson): PendienteGimnasio? = PendienteGimnasio(
            v["id"]?.comoTexto ?: return null, v["gimnasioId"]?.comoTexto ?: return null, v["zona"]?.comoTexto ?: return null, v["pregunta"]?.comoTexto,
        )

        fun leerCola(disco: Disco): List<PendienteGimnasio> {
            val j = disco.leer(ARCHIVO) ?: return emptyList()
            return (ValorJson.desde(j) as? ValorJson.Lista)?.elementos?.mapNotNull(::desde) ?: emptyList()
        }
    }
}

/** Lo que el alumno ya mandó y sale cuando termine de subir la cola, aunque cierre la app. */
data class EnvioGimnasio(
    val tipo: Tipo,
    val gimnasioId: String,
    val noHay: List<String> = emptyList(),
    val nota: String = "",
    val consentimiento: String = "",
    val quitar: List<String> = emptyList(),
) {
    enum class Tipo { ENVIAR, RESPONDER }

    fun aValor(): ValorJson = ValorJson.objeto(
        "tipo" to ValorJson.Texto(tipo.name), "gimnasioId" to ValorJson.Texto(gimnasioId), "noHay" to textos(noHay), "nota" to ValorJson.Texto(nota),
        "consentimiento" to ValorJson.Texto(consentimiento), "quitar" to textos(quitar),
    )

    companion object {
        fun desde(v: ValorJson?): EnvioGimnasio? {
            v ?: return null
            val tipo = Tipo.entries.firstOrNull { it.name == v["tipo"]?.comoTexto } ?: return null
            return EnvioGimnasio(tipo, v["gimnasioId"]?.comoTexto ?: return null, listaTextos(v["noHay"]), v["nota"]?.comoTexto ?: "", v["consentimiento"]?.comoTexto ?: "", listaTextos(v["quitar"]))
        }
    }
}

private fun textos(l: Collection<String>): ValorJson = ValorJson.Lista(l.map { ValorJson.Texto(it) })
private fun listaTextos(v: ValorJson?): List<String> = (v as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList()

/** Lo que el alumno lleva hecho en el teléfono y todavía no le dijo al servidor. */
data class BorradorGimnasio(
    val gimnasioId: String? = null,
    val noHay: List<String> = emptyList(),
    val nota: String = "",
    val quitar: List<String> = emptyList(),
    val respuestas: Map<String, ValorJson> = emptyMap(),
    val avisoVersion: String? = null,
    val envio: EnvioGimnasio? = null,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            gimnasioId?.let { put("gimnasioId", ValorJson.Texto(it)) }
            put("noHay", textos(noHay)); put("nota", ValorJson.Texto(nota)); put("quitar", textos(quitar)); put("respuestas", ValorJson.Objeto(respuestas))
            avisoVersion?.let { put("avisoVersion", ValorJson.Texto(it)) }
            envio?.let { put("envio", it.aValor()) }
        },
    )

    companion object {
        const val ARCHIVO = "gimnasio-borrador.json"

        fun desde(v: ValorJson): BorradorGimnasio = BorradorGimnasio(
            v["gimnasioId"]?.comoTexto, listaTextos(v["noHay"]), v["nota"]?.comoTexto ?: "", listaTextos(v["quitar"]),
            (v["respuestas"] as? ValorJson.Objeto)?.campos ?: emptyMap(), v["avisoVersion"]?.comoTexto, EnvioGimnasio.desde(v["envio"]),
        )
    }
}

/**
 * Gimnasio por fotos. Mismo criterio de cola que [ModeloFotos]: en disco, sobrevive a cerrar la app y a quedarse sin señal,
 * un error del servidor (5xx o 429) no gasta la foto, y todo 4xx es definitivo. Con la palanca apagada [ModeloApp] no llama a
 * nada de esto: [estado] queda en null y no se ve ni se pide nada. Gemelo de ModeloGimnasio.swift.
 */
class ModeloGimnasio(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    /** Espera entre reintentos, en milisegundos (en las pruebas, nada). */
    private val esperar: suspend (Long) -> Unit = { delay(it) },
    private val lanzar: (suspend () -> Unit) -> Unit = {},
) {
    enum class Salida { OK, SIN_SENAL, ERROR, TOKEN_CAIDO }
    enum class Foto { GUARDADA, TOPE, NO_SE_GUARDO }

    sealed interface AvisoEnvio {
        data class Faltan(val zonas: List<String>) : AvisoEnvio
        data object SinConsentimiento : AvisoEnvio
        data object SinNovedad : AvisoEnvio
        data object Error : AvisoEnvio
    }

    data class VistaFoto(val id: String, val archivoLocal: File?, val subiendo: Boolean, val esperando: Boolean)

    private val _estado = MutableStateFlow<EstadoGimnasio?>(null)
    /** null: apagado, sin el servidor nuevo, o sin red la primera vez. No se muestra nada. */
    val estado: StateFlow<EstadoGimnasio?> = _estado.asStateFlow()
    private val _cola = MutableStateFlow(disco?.let { PendienteGimnasio.leerCola(it) } ?: emptyList())
    val cola: StateFlow<List<PendienteGimnasio>> = _cola.asStateFlow()
    private val _subiendo = MutableStateFlow<String?>(null)
    val subiendo: StateFlow<String?> = _subiendo.asStateFlow()
    private val _urls = MutableStateFlow<Map<String, String>>(emptyMap())
    val urls: StateFlow<Map<String, String>> = _urls.asStateFlow()
    private val _avisoFoto = MutableStateFlow<Gimnasio.AvisoFoto?>(null)
    val avisoFoto: StateFlow<Gimnasio.AvisoFoto?> = _avisoFoto.asStateFlow()
    private val _avisoEnvio = MutableStateFlow<AvisoEnvio?>(null)
    val avisoEnvio: StateFlow<AvisoEnvio?> = _avisoEnvio.asStateFlow()
    private val _subidasEnvio = MutableStateFlow(0)
    val subidasEnvio: StateFlow<Int> = _subidasEnvio.asStateFlow()
    private val _totalEnvio = MutableStateFlow(0)
    val totalEnvio: StateFlow<Int> = _totalEnvio.asStateFlow()
    private val _borrador = MutableStateFlow(disco?.leer(BorradorGimnasio.ARCHIVO)?.let { BorradorGimnasio.desde(ValorJson.desde(it)) } ?: BorradorGimnasio())
    val borrador: StateFlow<BorradorGimnasio> = _borrador.asStateFlow()

    private val drenando = Mutex()
    private val mandandoEnvio = AtomicBoolean(false)
    private val reintentoProgramado = AtomicBoolean(false)
    private val conError = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val borrarAlSubir = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    @Volatile private var urlsVencen: Long? = null
    @Volatile private var reintentosDeFondo = 0

    /** La palanca `gimnasio_fotos` que se leyó por última vez: prendida, sin red en el gimnasio se pueden seguir sacando fotos. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    // ── Lo que lee la pantalla ──

    val abierta: CargaGimnasio? get() = _estado.value?.abierta
    val vigente: CargaGimnasio? get() = _estado.value?.vigente
    val tarjetaVisible: Boolean get() = Gimnasio.tarjetaVisible(_estado.value != null, abierta?.estado, vigente != null)
    val entradaVisible: Boolean get() = Gimnasio.entradaVisible(_estado.value != null, vigente != null)
    val pantalla: Gimnasio.Pantalla get() = Gimnasio.pantalla(abierta?.estado, vigente != null)

    /** El aviso de terceros, una sola vez: si el servidor no lo tiene aceptado y en este teléfono no se aceptó esta versión. */
    val necesitaAviso: Boolean get() = _estado.value?.let { !it.consentimientoAceptado && _borrador.value.avisoVersion != it.consentimientoVersion } ?: false

    private val colaDeLaCarga: List<PendienteGimnasio>
        get() {
            val a = abierta ?: return emptyList()
            val enServidor = a.fotos.map { it.id }.toSet()
            return _cola.value.filter { it.gimnasioId == a.id && it.id !in enServidor }
        }

    val zonasConFotos: Set<String> get() = (abierta?.fotos?.map { it.zona } ?: emptyList<String>()).toSet() + colaDeLaCarga.map { it.zona }
    val noHay: Set<String> get() = _borrador.value.noHay.toSet()
    val faltantes: List<String> get() = abierta?.let { Gimnasio.zonasFaltantes(zonasConFotos, noHay, it.modo) } ?: emptyList()
    val puedeEnviar: Boolean get() = abierta?.let { Gimnasio.puedeEnviar(it.modo, zonasConFotos, noHay, _borrador.value.quitar.toSet()) } ?: false
    val puedeAgregar: Boolean get() = Gimnasio.puedeAgregar(abierta?.fotos?.size ?: 0, colaDeLaCarga.size)
    val totalFotos: Int get() = (abierta?.fotos?.size ?: 0) + colaDeLaCarga.size

    fun fotos(zona: String): List<VistaFoto> {
        val sub = _subiendo.value
        return (abierta?.fotos ?: emptyList()).filter { it.zona == zona }.map { VistaFoto(it.id, null, subiendo = false, esperando = false) } +
            colaDeLaCarga.filter { it.zona == zona }.map { VistaFoto(it.id, archivo(it.id), sub == it.id, sub != it.id) }
    }

    // ── Servidor ──

    /** `get`. Sin el servidor nuevo o apagado para esta cuenta: nada. Sin red, lo último que se supo. */
    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_gimnasio_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) {
                    _estado.value = null
                    return
                }
                val e = EstadoGimnasio.desde(r.valor)
                if (e == null) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                    return
                }
                aplicar(e)
                disco?.guardar(ARCHIVO_ESTADO, r.valor)
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                } else if (_estado.value == null) {
                    disco?.leer(ARCHIVO_ESTADO)?.let { EstadoGimnasio.desde(ValorJson.desde(it)) }?.let(::aplicar)
                }
            }
        }
    }

    fun apagar() {
        _estado.value = null
    }

    private fun aplicar(e: EstadoGimnasio) {
        _estado.value = e
        var b = _borrador.value
        val id = e.abierta?.id
        if (b.gimnasioId != id) b = BorradorGimnasio(gimnasioId = id, avisoVersion = b.avisoVersion, envio = b.envio?.takeIf { it.gimnasioId == id })
        val en = b.envio
        val a = e.abierta
        // Lo que el servidor ya tomó deja de estar pendiente (un reintento devuelve `ya`).
        if (en != null && a != null && ((en.tipo == EnvioGimnasio.Tipo.ENVIAR && a.estado != "borrador") || (en.tipo == EnvioGimnasio.Tipo.RESPONDER && a.estado != "a_confirmar"))) {
            b = b.copy(envio = null)
        }
        if (b != _borrador.value) guardar(b)
    }

    suspend fun empezar(modo: String = "completa"): Salida {
        _estado.value?.let { e -> guardar(_borrador.value.copy(avisoVersion = e.consentimientoVersion)) }
        return nuevo(modo, 1)
    }

    fun aceptarAviso() {
        val e = _estado.value ?: return
        guardar(_borrador.value.copy(avisoVersion = e.consentimientoVersion))
    }

    private suspend fun nuevo(modo: String, reintentos: Int): Salida {
        return when (val r = cliente.llamar("mypump_gimnasio_nuevo", mapOf("p_token" to ValorJson.Texto(token), "p_modo" to ValorJson.Texto(modo)))) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) return Salida.TOKEN_CAIDO
                if (r.valor["ok"] == ValorJson.Booleano(true)) {
                    refrescar()
                    return Salida.OK
                }
                when (r.valor["error"]?.comoTexto) {
                    "sin_gimnasio_vigente" -> nuevo("completa", reintentos)
                    "no_habilitado" -> {
                        apagar()
                        Salida.ERROR
                    }
                    "reintentar" -> if (reintentos > 0) nuevo(modo, reintentos - 1) else Salida.ERROR
                    else -> Salida.ERROR
                }
            }
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) Salida.ERROR else Salida.SIN_SENAL
        }
    }

    // ── Fotos ──

    /** Encola el JPEG ya reducido (1600 px, 0,8, sin EXIF). Después hay que drenar. */
    fun agregar(zona: String, jpeg: ByteArray, pregunta: String? = null): Foto {
        val a = abierta ?: return Foto.NO_SE_GUARDO
        val d = disco ?: return Foto.NO_SE_GUARDO
        if (!puedeAgregar) {
            _avisoFoto.value = Gimnasio.AvisoFoto.TOPE
            return Foto.TOPE
        }
        val id = UUID.randomUUID().toString().lowercase()
        if (!escribirAtomico(archivo(id), jpeg)) return Foto.NO_SE_GUARDO
        val item = PendienteGimnasio(id, a.id, zona, pregunta)
        _cola.update { it + item }
        if (!guardarCola()) {
            _cola.update { l -> l.filter { it.id != id } }
            d.archivo("${PendienteGimnasio.CARPETA}/$id.jpg").delete()
            return Foto.NO_SE_GUARDO
        }
        _avisoFoto.value = null
        var b = _borrador.value
        if (zona in b.noHay) b = b.copy(noHay = b.noHay - zona)
        if (pregunta != null) b = b.copy(respuestas = b.respuestas + (pregunta to ValorJson.Texto("subida")))
        if (b != _borrador.value) guardar(b)
        return Foto.GUARDADA
    }

    suspend fun borrarFoto(id: String): Salida {
        if (_subiendo.value == id) {
            borrarAlSubir.add(id)
            sacarDeLaCola(id)
            return Salida.OK
        }
        if (_cola.value.any { it.id == id }) {
            sacarDeLaCola(id)
            return Salida.OK
        }
        val r = postVision("gimnasio/borrar", ValorJson.objeto("token" to ValorJson.Texto(token), "foto_id" to ValorJson.Texto(id))) ?: return Salida.SIN_SENAL
        if (r.first !in 200..299 || r.second?.get("ok") != ValorJson.Booleano(true)) {
            refrescar()
            return Salida.ERROR
        }
        _estado.update { e ->
            val a = e?.abierta ?: return@update e
            e.copy(abierta = a.copy(fotos = a.fotos.filter { it.id != id }))
        }
        return Salida.OK
    }

    private fun sacarDeLaCola(id: String) {
        val quitada = _cola.value.firstOrNull { it.id == id }
        _cola.update { l -> l.filter { it.id != id } }
        guardarCola()
        archivo(id).delete()
        val p = quitada?.pregunta
        if (p != null && _cola.value.none { it.pregunta == p } && p in _borrador.value.respuestas) {
            guardar(_borrador.value.copy(respuestas = _borrador.value.respuestas - p))
        }
    }

    fun marcarNoHay(zona: String, no: Boolean) {
        val s = _borrador.value.noHay.toMutableSet()
        if (no) s += zona else s -= zona
        guardar(_borrador.value.copy(noHay = Gimnasio.zonas.map { it.clave }.filter { it in s }))
    }

    fun fijarNota(s: String) {
        val n = Gimnasio.notaRecortada(s)
        if (n != _borrador.value.nota) guardar(_borrador.value.copy(nota = n))
    }

    fun alternarQuitar(tipo: String) {
        val q = _borrador.value.quitar
        guardar(_borrador.value.copy(quitar = if (tipo in q) q - tipo else q + tipo))
    }

    fun responder(id: String, valor: ValorJson?) {
        val r = _borrador.value.respuestas
        guardar(_borrador.value.copy(respuestas = if (valor == null) r - id else r + (id to valor)))
    }

    // ── Cola ──

    private sealed interface EnvioFoto {
        data object Ok : EnvioFoto
        data object Perdida : EnvioFoto
        data class Descartar(val s: Gimnasio.Subida) : EnvioFoto
        data object Reintentar : EnvioFoto
        data object Red : EnvioFoto
    }

    /**
     * Una pasada a la vez. Red: corta y espera a que vuelva. 5xx o 429: espera y reintenta, y a la tercera seguida deja esa foto
     * para el final y corta la pasada. Todo 4xx es definitivo. Al vaciarse la cola de la carga sale lo que el alumno haya mandado.
     */
    suspend fun drenar() {
        if (_estado.value == null || !drenando.tryLock()) return
        try {
            var refrescarAlFinal = false
            var seguidas = 0
            pasada@ while (true) {
                val item = _cola.value.sortedBy { if (it.id in conError) 1 else 0 }.firstOrNull { it.id !in borrarAlSubir } ?: break
                _subiendo.value = item.id
                val r = subir(item)
                _subiendo.value = null
                when (r) {
                    EnvioFoto.Ok -> {
                        sacarSubida(item)
                        seguidas = 0
                        reintentosDeFondo = 0
                        _subidasEnvio.update { it + 1 }
                    }
                    EnvioFoto.Perdida -> sacarDeLaCola(item.id)
                    is EnvioFoto.Descartar -> {
                        refrescarAlFinal = refrescarAlFinal || r.s.refrescar
                        r.s.aviso?.let { _avisoFoto.value = it }
                        descartar(item)
                    }
                    EnvioFoto.Reintentar -> {
                        conError.add(item.id)
                        seguidas++
                        if (seguidas >= MAX_INTENTOS_SEGUIDOS) {
                            programarReintento()
                            break@pasada
                        }
                        esperar(1000L shl seguidas)
                    }
                    EnvioFoto.Red -> break@pasada
                }
            }
            borrarAlSubir.clear()
            if (refrescarAlFinal) refrescar()
            mandarEnvio()
        } finally {
            drenando.unlock()
        }
    }

    /** Una pasada sin esperarla, atada a la vida de la app: cambiar de pantalla no corta la subida. */
    fun drenarEnFondo() {
        lanzar { drenar() }
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

    private suspend fun subir(p: PendienteGimnasio): EnvioFoto {
        val datos = try {
            archivo(p.id).readBytes()
        } catch (_: Exception) {
            return EnvioFoto.Perdida
        }
        val pedido = Pedido(
            url = "${cliente.config.vision}/gimnasio/upload", metodo = "POST",
            cabeceras = mapOf("Content-Type" to "image/jpeg", "x-gimnasio-token" to token, "x-gimnasio-id" to p.gimnasioId, "x-gimnasio-foto" to p.id, "x-gimnasio-zona" to p.zona),
            cuerpo = datos, esperaMs = 150_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return EnvioFoto.Red
        }
        val s = Gimnasio.clasificarSubida(r.status, parsear(r.cuerpo)?.get("ok") == ValorJson.Booleano(true))
        return when (s.accion) {
            Gimnasio.Accion.OK -> EnvioFoto.Ok
            Gimnasio.Accion.DESCARTAR -> EnvioFoto.Descartar(s)
            Gimnasio.Accion.REINTENTAR -> EnvioFoto.Reintentar
        }
    }

    private suspend fun sacarSubida(item: PendienteGimnasio) {
        conError.remove(item.id)
        _cola.update { l -> l.filter { it.id != item.id } }
        guardarCola()
        archivo(item.id).delete()
        if (borrarAlSubir.remove(item.id)) {
            borrarFoto(item.id)
        } else if (item.gimnasioId == abierta?.id && abierta?.fotos?.none { it.id == item.id } == true) {
            _estado.update { e ->
                val a = e?.abierta ?: return@update e
                e.copy(abierta = a.copy(fotos = a.fotos + FotoGimnasio(item.id, item.zona, if (a.estado == "borrador") 0 else 1)))
            }
            urlsVencen = null
        }
    }

    /** No va a entrar nunca. Si era para una pregunta, se le pide que la saque de nuevo. */
    private fun descartar(item: PendienteGimnasio) {
        sacarDeLaCola(item.id)
        conError.remove(item.id)
        if (item.pregunta != null && _borrador.value.envio?.tipo == EnvioGimnasio.Tipo.RESPONDER) guardar(_borrador.value.copy(envio = null))
    }

    // ── Enviar ──

    /** «Enviar a Mati»: queda anotado en disco y sale al vaciarse la cola; si no hay red, cuando vuelva. */
    suspend fun enviarCarga() {
        val a = abierta ?: return
        val e = _estado.value ?: return
        _avisoEnvio.value = null
        _totalEnvio.value = totalFotos
        _subidasEnvio.value = a.fotos.size
        val b = _borrador.value
        guardar(b.copy(envio = EnvioGimnasio(EnvioGimnasio.Tipo.ENVIAR, a.id, b.noHay, b.nota, e.consentimientoVersion, if (a.modo == "parcial") b.quitar else emptyList())))
        drenar()
    }

    /** Las respuestas de la ronda: salen después de las fotos que se pidieron. */
    suspend fun enviarRespuestas() {
        val a = abierta ?: return
        _avisoEnvio.value = null
        guardar(_borrador.value.copy(envio = EnvioGimnasio(EnvioGimnasio.Tipo.RESPONDER, a.id)))
        drenar()
    }

    private suspend fun mandarEnvio() {
        val e = _borrador.value.envio ?: return
        if (_cola.value.any { it.gimnasioId == e.gimnasioId } || !mandandoEnvio.compareAndSet(false, true)) return
        try {
            val base = mapOf("p_token" to ValorJson.Texto(token), "p_id" to ValorJson.Texto(e.gimnasioId))
            val r = when (e.tipo) {
                EnvioGimnasio.Tipo.ENVIAR -> cliente.llamar(
                    "mypump_gimnasio_enviar",
                    base + mapOf("p_no_hay" to textos(e.noHay), "p_nota" to ValorJson.Texto(e.nota), "p_consentimiento" to ValorJson.Texto(e.consentimiento), "p_quitar" to textos(e.quitar)),
                )
                EnvioGimnasio.Tipo.RESPONDER -> cliente.llamar(
                    "mypump_gimnasio_responder",
                    base + mapOf("p_respuestas" to ValorJson.Objeto(Gimnasio.respuestasParaEnviar(abierta?.preguntas ?: emptyList(), _borrador.value.respuestas))),
                )
            }
            when (r) {
                is Resultado.Ok -> alContestar(e, r.valor)
                is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) {   // 22023: error de programación, no se reintenta
                    guardar(_borrador.value.copy(envio = null))
                    _avisoEnvio.value = AvisoEnvio.Error
                }
            }
        } finally {
            mandandoEnvio.set(false)
        }
    }

    private suspend fun alContestar(e: EnvioGimnasio, j: ValorJson) {
        if (j == ValorJson.Nulo) return   // token caído: queda guardado para el link nuevo
        if (j["ok"] == ValorJson.Booleano(true)) {
            val b = _borrador.value
            guardar(b.copy(envio = null, respuestas = if (e.tipo == EnvioGimnasio.Tipo.RESPONDER) emptyMap() else b.respuestas))
            refrescar()
            return
        }
        guardar(_borrador.value.copy(envio = null))
        when (j["error"]?.comoTexto) {
            "faltan_zonas" -> _avisoEnvio.value = AvisoEnvio.Faltan(listaTextos(j["faltan"]))
            "sin_consentimiento" -> {
                guardar(_borrador.value.copy(avisoVersion = null))
                _avisoEnvio.value = AvisoEnvio.SinConsentimiento
                refrescar()
            }
            "sin_novedad" -> _avisoEnvio.value = AvisoEnvio.SinNovedad
            "no_encontrado", "estado_invalido" -> refrescar()
            "no_habilitado" -> apagar()
            else -> _avisoEnvio.value = AvisoEnvio.Error
        }
    }

    // ── Miniaturas ──

    /** URLs firmadas (1 h: se piden de nuevo a los 50 min o si aparece una que no estaba). */
    suspend fun firmar(gimnasioId: String, ids: List<String>, forzar: Boolean = false) {
        val vencen = urlsVencen
        if (!forzar && ids.all { it in _urls.value } && vencen != null && vencen > System.currentTimeMillis()) return
        val r = postVision("gimnasio/urls", ValorJson.objeto("token" to ValorJson.Texto(token), "gimnasio_id" to ValorJson.Texto(gimnasioId))) ?: return
        val filas = (r.second?.get("fotos") as? ValorJson.Lista)?.elementos
        if (r.second?.get("ok") != ValorJson.Booleano(true) || filas == null) return
        val mapa = _urls.value.toMutableMap()
        for (f in filas) {
            val i = f["id"]?.comoTexto
            val u = f["url"]?.comoTexto
            if (i != null && u != null) mapa[i] = u
        }
        _urls.value = mapa
        urlsVencen = System.currentTimeMillis() + 50 * 60 * 1000
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

    private fun parsear(cuerpo: ByteArray): ValorJson? = try {
        ValorJson.desde(Json.parseToJsonElement(cuerpo.toString(Charsets.UTF_8)))
    } catch (_: Exception) {
        null
    }

    // ── Disco ──

    fun archivo(id: String): File = disco?.archivo("${PendienteGimnasio.CARPETA}/$id.jpg") ?: File("/nonexistent/$id.jpg")

    private fun guardarCola(): Boolean {
        val d = disco ?: return false
        val c = _cola.value
        if (c.isEmpty()) {
            d.borrar(PendienteGimnasio.ARCHIVO)
            return true
        }
        return d.guardar(PendienteGimnasio.ARCHIVO, ValorJson.Lista(c.map { it.aValor() }))
    }

    private fun guardar(b: BorradorGimnasio) {
        _borrador.value = b
        disco?.guardar(BorradorGimnasio.ARCHIVO, b.aValor())
    }

    /** Las fotos que quedaron en la carpeta de otro link de la misma persona ([CuentasDelTelefono.adoptarGimnasio]). */
    internal fun adoptar(otras: List<PendienteGimnasio>, desde: Disco): Boolean {
        disco ?: return false
        for (p in otras) {
            if (_cola.value.any { it.id == p.id }) continue
            val datos = try {
                desde.archivo("${PendienteGimnasio.CARPETA}/${p.id}.jpg").readBytes()
            } catch (_: Exception) {
                continue
            }
            if (!escribirAtomico(archivo(p.id), datos)) continue
            _cola.update { it + p }
        }
        return guardarCola()
    }

    companion object {
        const val ARCHIVO_ESTADO = "gimnasio-estado.json"
        const val ARCHIVO_PALANCA = "gimnasio-palanca.json"
        const val MAX_INTENTOS_SEGUIDOS = 3
        const val MAX_REINTENTOS_DE_FONDO = 5
    }
}
