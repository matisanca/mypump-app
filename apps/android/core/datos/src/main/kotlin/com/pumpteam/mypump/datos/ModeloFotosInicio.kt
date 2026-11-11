package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EstadoFotosInicio
import com.pumpteam.mypump.reglas.FotoInicio
import com.pumpteam.mypump.reglas.FotosInicio
import java.io.File
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json

/** Una foto de inicio que espera subir. El JPEG va en su propio archivo (`fotos-inicio/<id>.jpg`) y acá solo el índice. */
data class PendienteFotoInicio(
    val id: String,
    val pose: String,
    /** ISO 8601 con zona: cuándo se sacó. */
    val tomadaEn: String,
    val brillo: Double? = null,
    val nitidez: Double? = null,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("id", ValorJson.Texto(id)); put("pose", ValorJson.Texto(pose)); put("tomadaEn", ValorJson.Texto(tomadaEn))
            brillo?.let { put("brillo", ValorJson.Numero(it)) }
            nitidez?.let { put("nitidez", ValorJson.Numero(it)) }
        },
    )

    companion object {
        const val ARCHIVO = "fotos-inicio-cola.json"
        const val CARPETA = "fotos-inicio"

        fun desde(v: ValorJson): PendienteFotoInicio? = PendienteFotoInicio(
            v["id"]?.comoTexto ?: return null, v["pose"]?.comoTexto ?: return null, v["tomadaEn"]?.comoTexto ?: return null,
            v["brillo"]?.comoNumero, v["nitidez"]?.comoNumero,
        )

        fun leerCola(disco: Disco): List<PendienteFotoInicio> {
            val j = disco.leer(ARCHIVO) ?: return emptyList()
            return (ValorJson.desde(j) as? ValorJson.Lista)?.elementos?.mapNotNull(::desde) ?: emptyList()
        }

        /** La nota que no se pudo mandar (sin red): sale con la cola. */
        fun leerNota(disco: Disco?): String? = disco?.leer(ModeloFotosInicio.ARCHIVO_NOTA)?.let { ValorJson.desde(it)["nota"]?.comoTexto }
    }
}

/**
 * Fotos de inicio (contrato, sección 13): frente, perfil y espalda, y «el físico que te motiva». La cola es la de Gimnasio:
 * en disco, sobrevive a cerrar la app y a quedarse sin señal, se sube de a una en el orden en que se encolaron, un error del
 * servidor (5xx o 429) no gasta la foto, y todo otro 4xx es definitivo ([FotosInicio.clasificarSubida]). Con la palanca
 * `fotos_inicio` apagada [ModeloApp] no llama a nada de esto: [estado] queda en null y no se ve ni se pide nada.
 */
class ModeloFotosInicio(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    /** Espera entre reintentos, en milisegundos (en las pruebas, nada). */
    private val esperar: suspend (Long) -> Unit = { delay(it) },
    private val lanzar: (suspend () -> Unit) -> Unit = {},
    /** El reloj de la caché de miniaturas (en las pruebas, uno que se adelanta). */
    private val ahora: () -> Long = System::currentTimeMillis,
) {
    enum class Salida { OK, SIN_SENAL, ERROR, TOKEN_CAIDO }
    enum class Foto { GUARDADA, TOPE, NO_SE_GUARDO }
    enum class EstadoPose { FALTA, SUBIENDO, ESPERANDO, LISTA }

    /** Lo que se ve de una foto: la del teléfono mientras espera subir, o la del servidor (con su miniatura firmada). */
    data class VistaFoto(val id: String, val pose: String, val archivoLocal: File?, val subiendo: Boolean, val esperando: Boolean)

    private val _estado = MutableStateFlow<EstadoFotosInicio?>(null)
    /** null: apagado, sin el servidor nuevo, token caído, o sin red y sin nada guardado. No se muestra nada. */
    val estado: StateFlow<EstadoFotosInicio?> = _estado.asStateFlow()
    private val _tokenCaido = MutableStateFlow(false)
    val tokenCaido: StateFlow<Boolean> = _tokenCaido.asStateFlow()
    private val _cola = MutableStateFlow(disco?.let { PendienteFotoInicio.leerCola(it) } ?: emptyList())
    val cola: StateFlow<List<PendienteFotoInicio>> = _cola.asStateFlow()
    private val _subiendo = MutableStateFlow<String?>(null)
    val subiendo: StateFlow<String?> = _subiendo.asStateFlow()
    private val _urls = MutableStateFlow<Map<String, String>>(emptyMap())
    val urls: StateFlow<Map<String, String>> = _urls.asStateFlow()
    private val _aviso = MutableStateFlow<FotosInicio.Aviso?>(null)
    val aviso: StateFlow<FotosInicio.Aviso?> = _aviso.asStateFlow()
    private val _notaPendiente = MutableStateFlow(PendienteFotoInicio.leerNota(disco))
    /** La nota que el alumno guardó sin red: se manda sola con la cola. */
    val notaPendiente: StateFlow<String?> = _notaPendiente.asStateFlow()

    init {
        barrerHuerfanos()
    }

    /** Un cierre entre el JPEG y el índice deja un archivo que nadie sube ni borra. */
    private fun barrerHuerfanos() {
        val carpeta = disco?.archivo(PendienteFotoInicio.CARPETA) ?: return
        val vivos = _cola.value.map { "${it.id}.jpg" }.toSet()
        carpeta.listFiles()?.filter { it.name !in vivos }?.forEach { it.delete() }
    }

    private val drenando = Mutex()
    private val mandandoNota = AtomicBoolean(false)
    private val reintentoProgramado = AtomicBoolean(false)
    private val conError = ConcurrentHashMap.newKeySet<String>()
    private val borrarAlSubir = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var urlsVencen: Long? = null
    @Volatile private var reintentosDeFondo = 0

    /** La palanca `fotos_inicio` que se leyó por última vez: prendida, sin red se pueden seguir sacando las fotos. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    // ── Lo que lee la pantalla ──

    /** La tarjeta de Revisión y la fila de Mis datos: solo con `habilitado: true`. */
    val visible: Boolean get() = _estado.value != null
    private val posesEnCola: Set<String> get() = _cola.value.map { it.pose }.filter { it != FotosInicio.MOTIVACION }.toSet()
    /** Las poses del cuerpo que faltan, contando las que esperan subir. */
    val faltan: List<String> get() = FotosInicio.faltan(_estado.value?.poses ?: emptySet(), posesEnCola)
    /** Cuántas de las tres ya están (en el servidor o esperando subir). */
    val hechas: Int get() = FotosInicio.poses.size - faltan.size
    /** Las tres en el servidor: Mati ya las tiene. */
    val listas: Boolean get() = _estado.value?.poses?.containsAll(FotosInicio.poses.map { it.clave }) == true

    fun estadoPose(pose: String): EstadoPose {
        val enCola = _cola.value.lastOrNull { it.pose == pose }
        return when {
            enCola != null -> if (_subiendo.value == enCola.id) EstadoPose.SUBIENDO else EstadoPose.ESPERANDO
            _estado.value?.foto(pose) != null -> EstadoPose.LISTA
            else -> EstadoPose.FALTA
        }
    }

    /** La foto que se muestra de una pose del cuerpo: la que espera subir (es la más nueva) o la del servidor. */
    fun foto(pose: String): VistaFoto? {
        val sub = _subiendo.value
        _cola.value.lastOrNull { it.pose == pose }?.let { return VistaFoto(it.id, pose, archivo(it.id), sub == it.id, sub != it.id) }
        return _estado.value?.foto(pose)?.let { VistaFoto(it.id, pose, null, subiendo = false, esperando = false) }
    }

    /** «El físico que te motiva»: las del servidor y después las que esperan subir. */
    val motivacion: List<VistaFoto>
        get() {
            val sub = _subiendo.value
            val enServidor = (_estado.value?.deMotivacion ?: emptyList()).map { VistaFoto(it.id, it.pose, null, subiendo = false, esperando = false) }
            val ids = enServidor.map { it.id }.toSet()
            return enServidor + _cola.value.filter { it.pose == FotosInicio.MOTIVACION && it.id !in ids && it.id !in borrarAlSubir }
                .map { VistaFoto(it.id, it.pose, archivo(it.id), sub == it.id, sub != it.id) }
        }

    val maxMotivacion: Int get() = _estado.value?.maxMotivacion ?: FotosInicio.MAX_MOTIVACION
    val puedeAgregarMotivacion: Boolean
        get() {
            val enServidor = _estado.value?.deMotivacion ?: emptyList()
            val ids = enServidor.map { it.id }.toSet()
            val enCola = _cola.value.count { it.pose == FotosInicio.MOTIVACION && it.id !in ids }
            return FotosInicio.puedeAgregarMotivacion(enServidor.size, enCola, maxMotivacion)
        }

    // ── Servidor ──

    /**
     * `get`. null es token caído; `habilitado:false`, sin el servidor nuevo (PGRST202, 404) o un rechazo: apagado. Sin red, lo
     * último que se supo.
     */
    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_fotos_inicio_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) {
                    _tokenCaido.value = true
                    _estado.value = null
                    return
                }
                _tokenCaido.value = false
                val e = EstadoFotosInicio.desde(r.valor)
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
                    disco?.leer(ARCHIVO_ESTADO)?.let { EstadoFotosInicio.desde(ValorJson.desde(it)) }?.let { _estado.value = it }
                }
            }
        }
    }

    fun apagar() {
        _estado.value = null
    }

    // ── Fotos ──

    /**
     * Encola el JPEG ya preparado (1600 px, 0,85, derecho y sin metadatos). Una pose del cuerpo saca de la cola a la anterior de
     * esa pose que todavía no empezó a subir. Después hay que drenar.
     */
    fun encolar(pose: String, jpeg: ByteArray, tomadaEn: OffsetDateTime, medida: FotosInicio.Medida? = null): Foto {
        if (_estado.value == null) return Foto.NO_SE_GUARDO
        val d = disco ?: return Foto.NO_SE_GUARDO
        if (pose != FotosInicio.MOTIVACION && FotosInicio.pose(pose) == null) return Foto.NO_SE_GUARDO
        if (pose == FotosInicio.MOTIVACION && !puedeAgregarMotivacion) {
            _aviso.value = FotosInicio.Aviso.TOPE
            return Foto.TOPE
        }
        val id = UUID.randomUUID().toString().lowercase()
        if (!escribirAtomico(archivo(id), jpeg)) return Foto.NO_SE_GUARDO
        val item = PendienteFotoInicio(id, pose, tomadaEn.truncatedTo(java.time.temporal.ChronoUnit.SECONDS).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME), medida?.brillo, medida?.nitidez)
        val anterior = _cola.value
        val reemplazadas = if (pose == FotosInicio.MOTIVACION) emptyList() else anterior.filter { it.pose == pose && it.id != _subiendo.value }
        _cola.value = anterior.filter { it !in reemplazadas } + item
        if (!guardarCola()) {
            _cola.value = anterior
            d.archivo("${PendienteFotoInicio.CARPETA}/$id.jpg").delete()
            return Foto.NO_SE_GUARDO
        }
        for (r in reemplazadas) {
            conError.remove(r.id)
            archivo(r.id).delete()
        }
        _aviso.value = null
        return Foto.GUARDADA
    }

    /** Solo las de motivación: las del cuerpo se reemplazan subiendo otra de la misma pose. */
    suspend fun borrarMotivacion(id: String): Salida {
        if (_subiendo.value == id) {
            borrarAlSubir.add(id)
            return Salida.OK
        }
        if (_cola.value.any { it.id == id }) {
            sacarDeLaCola(id)
            return Salida.OK
        }
        if (_estado.value?.deMotivacion?.any { it.id == id } != true) return Salida.ERROR
        val r = postVision("inicio/borrar", ValorJson.objeto("token" to ValorJson.Texto(token), "foto_id" to ValorJson.Texto(id))) ?: return Salida.SIN_SENAL
        if (r.first !in 200..299 || r.second?.get("ok") != ValorJson.Booleano(true)) {
            refrescar()
            return Salida.ERROR
        }
        actualizarEstado { e -> e.copy(fotos = e.fotos.filter { it.id != id }) }
        return Salida.OK
    }

    private fun sacarDeLaCola(id: String) {
        _cola.update { l -> l.filter { it.id != id } }
        guardarCola()
        archivo(id).delete()
        conError.remove(id)
    }

    fun limpiarAviso() {
        _aviso.value = null
    }

    // ── La nota ──

    /**
     * «Guardar nota». Sin red queda guardada en el teléfono ([notaPendiente]) y sale con la cola. El texto se recorta como lo
     * guarda el servidor ([FotosInicio.notaRecortada]).
     */
    suspend fun guardarNota(texto: String): Salida {
        if (_estado.value == null) return Salida.ERROR
        val n = FotosInicio.notaRecortada(texto)
        guardarBorradorNota(n)
        return mandarNota() ?: Salida.SIN_SENAL
    }

    /** null: se está mandando (otra pasada), o no hay nada que mandar. */
    private suspend fun mandarNota(): Salida? {
        val n = _notaPendiente.value ?: return null
        if (!mandandoNota.compareAndSet(false, true)) return null
        try {
            return when (val r = cliente.llamar("mypump_fotos_inicio_nota", mapOf("p_token" to ValorJson.Texto(token), "p_nota" to ValorJson.Texto(n)))) {
                is Resultado.Ok -> {
                    val j = r.valor
                    when {
                        // Token caído: queda guardada para el link nuevo.
                        j == ValorJson.Nulo -> {
                            _tokenCaido.value = true
                            Salida.TOKEN_CAIDO
                        }
                        j["ok"] == ValorJson.Booleano(true) -> {
                            val guardada = j["nota"]?.comoTexto ?: n
                            // Si mientras tanto escribió otra, esa sigue pendiente.
                            if (_notaPendiente.value == n) guardarBorradorNota(null)
                            actualizarEstado { it.copy(nota = guardada) }
                            Salida.OK
                        }
                        else -> {
                            guardarBorradorNota(null)
                            if (j["error"]?.comoTexto == "no_habilitado") apagar()
                            Salida.ERROR
                        }
                    }
                }
                is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    guardarBorradorNota(null)
                    Salida.ERROR
                } else {
                    Salida.SIN_SENAL
                }
            }
        } finally {
            mandandoNota.set(false)
        }
    }

    private fun guardarBorradorNota(n: String?) {
        _notaPendiente.value = n
        if (n == null) disco?.borrar(ARCHIVO_NOTA) else disco?.guardar(ARCHIVO_NOTA, ValorJson.objeto("nota" to ValorJson.Texto(n)))
    }

    // ── Cola ──

    private sealed interface Envio {
        data object Ok : Envio
        data object Perdida : Envio
        data class Descartar(val s: FotosInicio.Subida) : Envio
        data object Reintentar : Envio
        data object Red : Envio
    }

    /**
     * Una pasada a la vez. Sin red corta y espera a que vuelva. 5xx o 429: espera y reintenta, y a la tercera seguida corta la
     * pasada y vuelve a probar al minuto. Todo otro 4xx es definitivo. Al vaciarse la cola se refresca el estado y sale la nota
     * que había quedado guardada.
     */
    suspend fun drenar() {
        if (_estado.value == null || !drenando.tryLock()) return
        try {
            var refrescarAlFinal = false
            var subioAlguna = false
            var seguidas = 0
            pasada@ while (true) {
                sacarReemplazadas()
                val item = _cola.value.sortedBy { if (it.id in conError) 1 else 0 }.firstOrNull() ?: break
                _subiendo.value = item.id
                val r = subir(item)
                _subiendo.value = null
                // La borró mientras subía y no llegó a entrar: ya no se sube.
                if (r != Envio.Ok && borrarAlSubir.remove(item.id)) {
                    sacarDeLaCola(item.id)
                    if (r == Envio.Red) break@pasada
                    continue@pasada
                }
                when (r) {
                    Envio.Ok -> {
                        sacarSubida(item)
                        subioAlguna = true
                        seguidas = 0
                        reintentosDeFondo = 0
                    }
                    Envio.Perdida -> sacarDeLaCola(item.id)
                    is Envio.Descartar -> {
                        // 403: el link ya no sirve o se cerró la sección. Lo demás tampoco va a entrar, y la foto NO se borra:
                        // si es el link, sale con el nuevo (adoptarFotosInicio).
                        if (r.s.refrescar) {
                            refrescarAlFinal = true
                            break@pasada
                        }
                        r.s.aviso?.let { _aviso.value = it }
                        sacarDeLaCola(item.id)
                        borrarAlSubir.remove(item.id)
                    }
                    Envio.Reintentar -> {
                        conError.add(item.id)
                        seguidas++
                        if (seguidas >= MAX_INTENTOS_SEGUIDOS) {
                            programarReintento()
                            break@pasada
                        }
                        esperar(1000L shl seguidas)
                    }
                    Envio.Red -> break@pasada
                }
            }
            if (refrescarAlFinal || (subioAlguna && _cola.value.isEmpty())) refrescar()
            if (_estado.value != null && mandarNota() == Salida.SIN_SENAL) programarReintento()
        } finally {
            drenando.unlock()
        }
    }

    /**
     * Una foto del cuerpo que tiene otra más nueva de su pose en la cola ya no se sube (quedó de cuando la nueva se encoló
     * mientras esta subía): si se reintentara después, pisaría en el servidor a la que el alumno eligió.
     */
    private fun sacarReemplazadas() {
        val cuerpo = _cola.value.filter { it.pose != FotosInicio.MOTIVACION }
        val ultima = cuerpo.associate { it.pose to it.id }
        for (p in cuerpo) if (ultima[p.pose] != p.id) sacarDeLaCola(p.id)
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

    private suspend fun subir(p: PendienteFotoInicio): Envio {
        val datos = try {
            archivo(p.id).readBytes()
        } catch (_: Exception) {
            return Envio.Perdida
        }
        val cabeceras = buildMap {
            put("Content-Type", "image/jpeg")
            put("x-inicio-token", token)
            put("x-inicio-foto", p.id)
            put("x-inicio-pose", p.pose)
            put("x-inicio-tomada", p.tomadaEn)
            p.brillo?.let { put("x-inicio-brillo", numero(it)) }
            p.nitidez?.let { put("x-inicio-nitidez", numero(it)) }
        }
        val pedido = Pedido(url = "${cliente.config.vision}/inicio/upload", metodo = "POST", cabeceras = cabeceras, cuerpo = datos, esperaMs = 90_000)
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Envio.Red
        }
        val s = FotosInicio.clasificarSubida(r.status, parsear(r.cuerpo)?.get("ok") == ValorJson.Booleano(true))
        return when (s.accion) {
            FotosInicio.Accion.OK -> Envio.Ok
            FotosInicio.Accion.DESCARTAR -> Envio.Descartar(s)
            FotosInicio.Accion.REINTENTAR -> Envio.Reintentar
        }
    }

    /** Subió: el estado ya la muestra (reemplaza la de esa pose) sin esperar al servidor. */
    private suspend fun sacarSubida(item: PendienteFotoInicio) {
        sacarDeLaCola(item.id)
        if (borrarAlSubir.remove(item.id)) {
            // La borró mientras subía: ahora que está en el servidor se borra ahí.
            actualizarEstado { e -> e.copy(fotos = e.fotos + FotoInicio(item.id, item.pose, item.tomadaEn)) }
            borrarMotivacion(item.id)
            return
        }
        actualizarEstado { e ->
            val sinLaVieja = if (item.pose == FotosInicio.MOTIVACION) e.fotos.filter { it.id != item.id } else e.fotos.filter { it.pose != item.pose }
            e.copy(fotos = sinLaVieja + FotoInicio(item.id, item.pose, item.tomadaEn))
        }
        urlsVencen = null
    }

    private fun actualizarEstado(cambio: (EstadoFotosInicio) -> EstadoFotosInicio) {
        _estado.update { e -> e?.let(cambio) }
        val e = _estado.value ?: return
        disco?.guardar(ARCHIVO_ESTADO, aValor(e))
    }

    // ── Miniaturas ──

    /** URLs firmadas por 1 h: se piden de nuevo a los 50 min, o si aparece una foto que no estaba. */
    suspend fun firmar(forzar: Boolean = false) {
        val e = _estado.value ?: return
        val ids = e.fotos.map { it.id }
        if (ids.isEmpty()) return
        val vencen = urlsVencen
        if (!forzar && ids.all { it in _urls.value } && vencen != null && vencen > ahora()) return
        val r = postVision("inicio/urls", ValorJson.objeto("token" to ValorJson.Texto(token))) ?: return
        val filas = (r.second?.get("fotos") as? ValorJson.Lista)?.elementos
        if (r.second?.get("ok") != ValorJson.Booleano(true) || filas == null) return
        val mapa = HashMap<String, String>()
        for (f in filas) {
            val i = f["id"]?.comoTexto
            val u = f["url"]?.comoTexto
            if (i != null && u != null) mapa[i] = u
        }
        _urls.value = mapa
        urlsVencen = ahora() + 50 * 60 * 1000
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

    fun archivo(id: String): File = disco?.archivo("${PendienteFotoInicio.CARPETA}/$id.jpg") ?: File("/nonexistent/$id.jpg")

    private fun guardarCola(): Boolean {
        val d = disco ?: return false
        val c = _cola.value
        if (c.isEmpty()) {
            d.borrar(PendienteFotoInicio.ARCHIVO)
            return true
        }
        return d.guardar(PendienteFotoInicio.ARCHIVO, ValorJson.Lista(c.map { it.aValor() }))
    }

    /** Las fotos (y la nota) que quedaron en la carpeta de otro link de la misma persona ([CuentasDelTelefono.adoptarFotosInicio]). */
    internal fun adoptar(otras: List<PendienteFotoInicio>, desde: Disco): Boolean {
        disco ?: return false
        var todas = true
        for (p in otras) {
            if (_cola.value.any { it.id == p.id }) continue
            val datos = try {
                desde.archivo("${PendienteFotoInicio.CARPETA}/${p.id}.jpg").readBytes()
            } catch (_: Exception) {
                todas = false
                continue
            }
            if (!escribirAtomico(archivo(p.id), datos)) {
                todas = false
                continue
            }
            _cola.update { it + p }
        }
        if (_notaPendiente.value == null) PendienteFotoInicio.leerNota(desde)?.let { guardarBorradorNota(it) }
        return guardarCola() && todas
    }

    companion object {
        const val ARCHIVO_ESTADO = "fotos-inicio-estado.json"
        const val ARCHIVO_NOTA = "fotos-inicio-borrador.json"
        const val ARCHIVO_PALANCA = "fotos-inicio-palanca.json"
        const val MAX_INTENTOS_SEGUIDOS = 3
        const val MAX_REINTENTOS_DE_FONDO = 5

        private fun numero(d: Double): String = String.format(Locale.ROOT, "%.2f", d)

        /** El estado como lo devolvió el servidor, para guardarlo (el teléfono lo actualiza al subir sin esperar). */
        internal fun aValor(e: EstadoFotosInicio): ValorJson = ValorJson.objeto(
            "habilitado" to ValorJson.Booleano(true),
            "completo" to ValorJson.Booleano(e.completo),
            "nota" to ValorJson.Texto(e.nota),
            "max_motivacion" to ValorJson.Numero(e.maxMotivacion.toDouble()),
            "fotos" to ValorJson.Lista(
                e.fotos.map { f ->
                    ValorJson.Objeto(
                        buildMap {
                            put("id", ValorJson.Texto(f.id)); put("pose", ValorJson.Texto(f.pose))
                            f.tomadaEn?.let { put("tomada_en", ValorJson.Texto(it)) }
                            put("ancho", ValorJson.Numero(f.ancho.toDouble())); put("alto", ValorJson.Numero(f.alto.toDouble()))
                        },
                    )
                },
            ),
        )
    }
}
